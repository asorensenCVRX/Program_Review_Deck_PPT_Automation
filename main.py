from database import df, slide_10_df, slide_11_df, pat_access_df
from functions import (replace_chart_data, replace_text_on_slide, replace_table_data,
                       add_plus_if_needed, update_chart_cells, dataframe_to_cell_updates)
from pptx import Presentation
from pathlib import Path
from datetime import date, datetime
import pandas as pd
import time

# get data from the PowerPoint
ppt_path = r"C:\Users\asorensen\OneDrive - CVRx Inc\Projects\2026\20260623_Program_review_deck_automation_LJackson\TEMPLATE DECK.pptx"
out_path = Path(r"C:\Users\asorensen\OneDrive - CVRx Inc\Projects\2026\20260623_Program_review_deck_automation_LJackson\Q4 Review")
out_path.mkdir(parents=True, exist_ok=True)

# get previous 4 quarters to use as category names in the slides
today = date.today()
month_year = str(datetime.today().strftime("%B %Y"))
current_q = (today.month - 1) // 3 + 1
year = today.year
quarters = []
for i in range(1, 5):
    q = current_q - i
    y = year

    while q <= 0:
        q += 4
        y -= 1

    quarters.append(f"Q{q} '{str(y)[2:]}")
quarters.reverse()

for index, row in df.iterrows():
    print(f"Creating deck for {row['ACCOUNT_NAME']}...", end="", flush=True)
    prs = Presentation(ppt_path)

    #################################### SLIDE 1 ##########################################
    replace_text_on_slide(presentation=prs,
                          slide_number=1,
                          replacements={
                              "[Account Name]": row["ACCOUNT_NAME"],
                              "[Month and Year]": month_year
                          })

    #################################### SLIDE 4 ##########################################
    implants = [row["-4Q_IMPL"],
                row["-3Q_IMPL"],
                row["-2Q_IMPL"],
                row["-1Q_IMPL"]]
    patients_in_funnel = [row["-4Q_PATIENTS_IN_FUNNEL"],
                          row["-3Q_PATIENTS_IN_FUNNEL"],
                          row["-2Q_PATIENTS_IN_FUNNEL"],
                          row["-1Q_PATIENTS_IN_FUNNEL"]]
    ref_pres = [row["-4Q_REF_PRES"],
                row["-3Q_REF_PRES"],
                row["-2Q_REF_PRES"],
                row["-1Q_REF_PRES"]]
    implants_prior_quarter = str(row["-1Q_IMPL"] - row["-2Q_IMPL"])
    implants_delta = add_plus_if_needed(str((row["-1Q_IMPL"] - row["-2Q_IMPL"]) - (row["-2Q_IMPL"] - row["-3Q_IMPL"])))
    implanters_prior_quarter = str(row["C12_IMPLANTERS"])
    implanters_delta = add_plus_if_needed(str(row["C12_IMPLANTERS"] - row["R12_IMPLANTERS"]))
    inpatient_delta = add_plus_if_needed(str(round((row["R12_IP_MIX"] - row["PREV_R12_IP_MIX"]) * 100)))
    outpatient_delta = add_plus_if_needed(str(round((row["R12_OP_MIX"] - row["PREV_R12_OP_MIX"]) * 100)))

    replace_chart_data(presentation=prs,
                       slide_number=4,
                       shape_number=15,
                       categories=quarters,
                       series_data={
                           "Implants": implants
                       })
    replace_chart_data(presentation=prs,
                       slide_number=4,
                       shape_number=16,
                       categories=quarters,
                       series_data={
                           "Referrers/Prescribers": ref_pres
                       })
    replace_chart_data(presentation=prs,
                       slide_number=4,
                       shape_number=17,
                       categories=quarters,
                       series_data={
                           "Patients in Funnel": patients_in_funnel
                       })
    replace_text_on_slide(presentation=prs,
                          slide_number=4,
                          replacements={
                              "[A]": implants_prior_quarter,
                              "[B]": implants_delta,
                              "[C]": implanters_prior_quarter,
                              "[D]": implanters_delta,
                              "[E]": str(round(row["R12_IP_MIX"] * 100)),
                              "[F]": str(round(row["R12_OP_MIX"] * 100)),
                              "[G]": inpatient_delta,
                              "[H]": outpatient_delta
                          })
    #################################### SLIDE 7/8 ########################################
    replace_text_on_slide(presentation=prs,
                          slide_number=7,
                          replacements={
                              "[A]": str(row["-1Q_CPAS"]),
                              "[B]": add_plus_if_needed(str((row["-1Q_CPAS"] - row["-2Q_CPAS"])))
                          })
    for i in [7, 8]:
        replace_table_data(presentation=prs,
                           slide_number=i,
                           shape_number=2,
                           data=pd.DataFrame({"payment": [
                               f"${float(row['pay_1580']):,.0f}",
                               f"${float(row['pay_drg_276']):,.0f}"
                           ]}),
                           column_mapping={
                               3: "payment",
                           },
                           start_row=2)

    patient_access = pat_access_df.loc[
        pat_access_df["ACT_ID"] == row["ACT_ID"],
        ["MedicareAdv_SubType", "R4Q_DAY_30_APPROVAL", "-1Q_DAY_30_APPROVAL", "-1Q_ELIGIBLE_SUBMISSIONS",
         "R4Q_ELIGIBLE_SUBMISSIONS"]
    ]
    # convert nan values to None
    patient_access = patient_access.astype(object).where(patient_access.notna(), None)
    # CONTINUES THE CHART UPDATE AT THE END OF THE LOOP
    #################################### SLIDE 10 #########################################
    slide_10_ref = (
        slide_10_df.loc[
            (
                    (slide_10_df["ACT_ID"] == row["ACT_ID"])
                    & (slide_10_df["DATASET"] == "REF/PRES")
            ),
            [
                "PHYSICIAN",
                "-1Q_PAT_IDENTIFIED",
                "QTLY_AVG_PAT_IDENTIFIED",
                "-1Q_PATS_IMPL",
                "QTLY_AVG_PAT_IMPLANTED",
            ],
        ].reset_index(drop=True)
    )
    replace_table_data(presentation=prs,
                       slide_number=10,
                       shape_number=2,
                       data=slide_10_ref,
                       column_mapping={
                               0: "PHYSICIAN",
                               1: "-1Q_PAT_IDENTIFIED",
                               2: "QTLY_AVG_PAT_IDENTIFIED",
                               3: "-1Q_PATS_IMPL",
                               4: "QTLY_AVG_PAT_IMPLANTED"
                           },
                       start_row=2)

    slide_10_implanters = (
        slide_10_df.loc[
            (
                    (slide_10_df["ACT_ID"] == row["ACT_ID"])
                    & (slide_10_df["DATASET"] == "IMPLANTER")
            ),
            [
                "PHYSICIAN",
                "-1Q_PATS_IMPL",
                "QTLY_AVG_PAT_IMPLANTED"
            ]
        ].reset_index(drop=True)
    )
    replace_table_data(presentation=prs,
                       slide_number=10,
                       shape_number=3,
                       data=slide_10_implanters,
                       column_mapping={
                           0: "PHYSICIAN",
                           1: "-1Q_PATS_IMPL",
                           2: "QTLY_AVG_PAT_IMPLANTED",
                       },
                       start_row=2)
    #################################### SLIDE 11 #########################################
    replace_text_on_slide(presentation=prs,
                          slide_number=11,
                          replacements={
                              "[A]": str(row["R6_REF_PRES (INCL NO IMPLANT)"]),
                              "[B]": str(slide_11_df["R6_REF_PRES"][0]),
                              "[C]": str(row["R6_PATIENTS_IN_FUNNEL"]),
                              "[D]": str(slide_11_df["R6_OPPS_CREATED"][0]),
                              "[E]": "N/A" if pd.isna(row["R6_AVG_TIME_TO_IMPL"]) else str(int(row["R6_AVG_TIME_TO_IMPL"])),
                              "[F]": str(slide_11_df["R6_AVG_TIME_TO_IMPL"][0]),
                              "[G]": str(row["R6_IMPLANTS"]),
                              "[H]": str(slide_11_df["R6_IMPL_VOL"][0])
                          })
    #######################################################################################
    save_name = f'{row["ACCOUNT_NAME"]} Q{current_q} Review.pptx'
    save_path = (str(out_path / save_name))
    prs.save(save_path)
    time.sleep(2)
    #################################### SLIDE 7 CHART #########################################
    cell_updates = dataframe_to_cell_updates(
        dataframe=patient_access,
        column_mapping={
            "A": "MedicareAdv_SubType",
            "B": "R4Q_DAY_30_APPROVAL",
            "C": "-1Q_DAY_30_APPROVAL",
            "D": "R4Q_ELIGIBLE_SUBMISSIONS",
            "E": "-1Q_ELIGIBLE_SUBMISSIONS",
        },
        start_row=3
    )

    update_chart_cells(ppt_path=save_path,
                       output_path=save_path,
                       slide_number=7,
                       shape_number=7,
                       cell_values=cell_updates)

    print("done")


