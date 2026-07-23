import win32com
from pptx.chart.data import CategoryChartData
from collections.abc import Mapping, Sequence
from pptx import Presentation
import win32com.client as win32
from pathlib import Path
import time

ppt_path = r"C:\Users\asorensen\OneDrive - CVRx Inc\Projects\2026\20260623_Program_review_deck_automation_LJackson\TEMPLATE DECK.pptx"

def get_charts(presentation, slide_number: int):
    """use this to find the chart you want to edit"""
    slide_num = presentation.slides[slide_number - 1]
    for i, shape in enumerate(slide_num.shapes):
        if shape.has_chart:
            print(f"shape number: {i}, shape name: {shape.name}")

# get_charts(presentation=Presentation(ppt_path), slide_number=7)

def get_tables(presentation, slide_number: int):
    """Print the shape index and dimensions of each table on a slide."""
    slide = presentation.slides[slide_number - 1]

    for i, shape in enumerate(slide.shapes):
        if shape.has_table:
            table = shape.table
            print(
                f"Shape index: {i}",
                f"Name: {shape.name}",
                f"Rows: {len(table.rows)}",
                f"Columns: {len(table.columns)}",
                sep=" | "
            )

# get_tables(presentation=Presentation(ppt_path), slide_number=8)

def replace_chart_data(presentation,
                       slide_number: int,
                       shape_number: int,
                       categories: Sequence,
                       series_data: Mapping[str, Sequence],
                       series_number_formats: Mapping[str, str] | None = None
                       ):
    """
    Replace a chart's embedded data with one or more data series.

    Parameters
    ----------
    presentation
        A python-pptx Presentation object.
    slide_number : int
        One-based slide number.
    shape_number : int
        Zero-based shape index on the slide.
    categories : Sequence
        Category labels for the chart.
    series_data : Mapping[str, Sequence]
        Dictionary containing series names and their corresponding values.

        Example:
        {
            "Implants": [10, 15, 20],
            "Activations": [8, 12, 18],
        }
    """
    slide = presentation.slides[slide_number - 1]
    chart = slide.shapes[shape_number].chart

    chart_data = CategoryChartData()
    chart_data.categories = categories

    series_number_formats = series_number_formats or {}

    for series_name, values in series_data.items():
        number_format = series_number_formats.get(series_name, "General")

        chart_data.add_series(series_name, values, number_format=number_format)
    # replace embedded chart data
    chart.replace_data(chart_data)

def replace_text_on_slide(presentation, slide_number: int, replacements):
    slide = presentation.slides[slide_number - 1]
    for shape in slide.shapes:
        if shape.has_text_frame:
            for paragraph in shape.text_frame.paragraphs:
                for run in paragraph.runs:
                    for old, new in replacements.items():
                        if old in run.text:
                            run.text = run.text.replace(old, new)

def set_cell_text(cell, value):
    """Replace cell text while retaining the first run's formatting."""
    value = "" if value is None else str(value)

    text_frame = cell.text_frame

    if not text_frame.paragraphs:
        paragraph = text_frame.add_paragraph()
    else:
        paragraph = text_frame.paragraphs[0]

    if paragraph.runs:
        paragraph.runs[0].text = value

        # Remove any additional runs.
        for run in paragraph.runs[1:]:
            run.text = ""
    else:
        paragraph.add_run().text = value

    # Clear any additional paragraphs.
    for extra_paragraph in text_frame.paragraphs[1:]:
        extra_paragraph.text = ""

def replace_table_data(
    presentation,
    slide_number: int,
    shape_number: int,
    data,
    column_mapping: dict,
    start_row: int = 1,
    max_data_rows: int | None = None
):
    """
    Replace PowerPoint table data using a pandas DataFrame.

    Parameters
    ----------
    presentation:
        python-pptx Presentation object.

    slide_number:
        PowerPoint slide number, starting at 1.

    shape_number:
        Shape index containing the PowerPoint table.

    data:
        pandas DataFrame containing the replacement data.

    column_mapping:
        Maps PowerPoint table column indexes to DataFrame column names.

        Example:
        {
            0: "REFERRER_NAME",
            1: "PRIOR_QUARTER_PATIENTS",
            2: "R12_QUARTERLY_AVG"
        }

    start_row:
        PowerPoint table row where data entry should begin.
        This is zero-based:
            0 = first row
            1 = second row
            2 = third row

    max_data_rows:
        Optional maximum number of DataFrame rows to write.
    """
    slide = presentation.slides[slide_number - 1]
    shape = slide.shapes[shape_number]

    if not shape.has_table:
        raise ValueError(
            f"Shape {shape_number} on slide {slide_number} is not a table."
        )

    table = shape.table
    total_table_rows = len(table.rows)

    if start_row < 0 or start_row >= total_table_rows:
        raise ValueError(
            f"start_row must be between 0 and {total_table_rows - 1}."
        )

    available_data_rows = total_table_rows - start_row

    if max_data_rows is not None:
        available_data_rows = min(
            available_data_rows,
            max_data_rows
        )

    # Clear existing table data beginning at start_row.
    for table_row in range(start_row, total_table_rows):
        for table_col in column_mapping:
            set_cell_text(
                table.cell(table_row, table_col),
                ""
            )

    # Fill the table beginning at start_row.
    for output_row, (_, record) in enumerate(
        data.head(available_data_rows).iterrows(),
        start=start_row
    ):
        for table_col, dataframe_column in column_mapping.items():
            value = record[dataframe_column]

            if value is None:
                display_value = ""
            elif isinstance(value, float) and value.is_integer():
                display_value = str(int(value))
            else:
                display_value = str(value)

            set_cell_text(
                table.cell(output_row, table_col),
                display_value
            )

def add_plus_if_needed(value: str) -> str:
    """Prefix '+' unless the string already starts with '-' or '+'."""
    if value.startswith(("-", "+")):
        return value
    return f"+{value}"

def update_chart_cells(
    ppt_path,
    output_path,
    slide_number,
    shape_number,
    cell_values,
    worksheet_number=1,
):
    """
    Update specific cells in a PowerPoint chart's embedded Excel workbook.

    cell_values example:
        {
            "B2": 0.75,
            "B3": 0.82,
            "C2": 0.68,
            "C3": 0.79,
        }

    Only the specified cells are changed. Existing chart series,
    helper columns, formulas, formatting, and data-label references remain.
    """
    shape_number = shape_number + 1

    ppt_path = str(Path(ppt_path).resolve())
    output_path = str(Path(output_path).resolve())

    powerpoint = win32.DispatchEx("PowerPoint.Application")
    powerpoint.Visible = True

    presentation = None
    workbook = None

    try:
        presentation = powerpoint.Presentations.Open(
            ppt_path,
            WithWindow=False,
        )

        slide = presentation.Slides(slide_number)
        shape = slide.Shapes(shape_number)

        if not shape.HasChart:
            raise ValueError(
                f"Shape {shape_number} on slide {slide_number} "
                "is not a chart."
            )

        chart = shape.Chart

        # Opens the chart's embedded Excel workbook.
        chart.ChartData.Activate()

        workbook = chart.ChartData.Workbook
        worksheet = workbook.Worksheets(worksheet_number)

        worksheet.Range("A3:E7").ClearContents()

        for cell_address, value in cell_values.items():
            worksheet.Range(cell_address).Value = value

        # Recalculate formulas in the embedded workbook.
        workbook.Application.CalculateFullRebuild()

        # Redraw the PowerPoint chart using the updated worksheet data.
        chart.Refresh()

        time.sleep(5)

        # Commit edits to the embedded workbook.
        workbook.Close(SaveChanges=True)
        workbook = None

        # Refresh again after the workbook closes.
        chart.Refresh()

        # Save the PowerPoint.
        if ppt_path == output_path:
            presentation.Save()
        else:
            presentation.SaveAs(str(output_path))


    finally:

        if workbook is not None:
            try:
                workbook.Close(SaveChanges=True)
            except Exception:
                pass

        if presentation is not None:
            try:
                presentation.Close()
            except Exception:
                pass

        try:
            powerpoint.Quit()
        except Exception:
            pass

def dataframe_to_cell_updates(
    dataframe,
    column_mapping,
    start_row=2,
):
    """
    column_mapping example:
        {
            "B": "R4Q_DAY_30_APPROVAL",
            "C": "-1Q_DAY_30_APPROVAL",
        }
    """

    updates = {}

    for excel_column, dataframe_column in column_mapping.items():
        for row_offset, value in enumerate(
            dataframe[dataframe_column].tolist()
        ):
            excel_row = start_row + row_offset

            if value is None or value != value:
                value = None

            updates[f"{excel_column}{excel_row}"] = value

    return updates