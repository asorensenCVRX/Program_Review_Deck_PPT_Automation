DECLARE @MINUS1Q AS VARCHAR(7) = CONCAT(
    YEAR(DATEADD(QUARTER, -1, GETDATE())),
    '_Q',
    DATEPART(QUARTER, DATEADD(QUARTER, -1, GETDATE()))
),
@MINUS2Q AS VARCHAR(7) = CONCAT(
    YEAR(DATEADD(QUARTER, -2, GETDATE())),
    '_Q',
    DATEPART(QUARTER, DATEADD(QUARTER, -2, GETDATE()))
),
@MINUS3Q AS VARCHAR(7) = CONCAT(
    YEAR(DATEADD(QUARTER, -3, GETDATE())),
    '_Q',
    DATEPART(QUARTER, DATEADD(QUARTER, -3, GETDATE()))
),
@MINUS4Q AS VARCHAR(7) = CONCAT(
    YEAR(DATEADD(QUARTER, -4, GETDATE())),
    '_Q',
    DATEPART(QUARTER, DATEADD(QUARTER, -4, GETDATE()))
),
/* To run this query for a specific month, change the GETDATE() in the following 5 lines to the first day 
 of the month you want to run the query for. You will also need to change the GETDATE() in the variables
 in the national_perspective.sql file, although there is a chance you need to copy those values into the
 slide manually because there may be more approvals or more eligible submissions than when you last ran 
 the script. NOTHING ELSE NEEDS TO BE CHANGED IN ANY OF THE OTHER QUERIES,
 UNLESS YOU ARE RUNNING FOR A DIFFERENT QUARTER THAN THE ONE YOU ARE CURRENTLY IN. */
@MONTH_MINUS_12 AS VARCHAR(7) = FORMAT(DATEADD(MONTH, -12, GETDATE()), 'yyyy_MM'),
@MONTH_MINUS_1 AS VARCHAR(7) = FORMAT(DATEADD(MONTH, -1, GETDATE()), 'yyyy_MM'),
@MONTH_MINUS_24 AS VARCHAR(7) = FORMAT(DATEADD(MONTH, -24, GETDATE()), 'yyyy_MM'),
@MONTH_MINUS_13 AS VARCHAR(7) = FORMAT(DATEADD(MONTH, -13, GETDATE()), 'yyyy_MM'),
@MONTH_MINUS_6 AS VARCHAR(7) = FORMAT(DATEADD(MONTH, -6, GETDATE()), 'yyyy_MM');

WITH OPPS AS (
    SELECT
        O.CREATEDDATE,
        O.CREATED_YYYYMM,
        O.CREATED_YYYYQQ,
        O.CLOSEDATE,
        O.CLOSE_YYYYMM,
        O.CLOSE_YYYYQQ,
        O.IMPLANTED_DT,
        O.IMPLANTED_YYYYMM,
        O.IMPLANTED_YYYYQQ,
        DATEDIFF(DAY, O.CREATEDDATE, O.IMPLANTED_DT) AS TIME_TO_IMPL,
        A.NAME AS ACCOUNT_NAME,
        ACT_ID,
        O.NAME AS OPP_NAME,
        OPP_ID,
        IMPLANT_UNITS,
        REVENUE_UNITS,
        SALES,
        REASON_FOR_IMPLANT__C,
        INDICATION_FOR_USE__C,
        O.OPP_STATUS,
        O.PHYSICIAN_ID,
        O.PRESCRIBER_ID,
        O.SURGEON_ID,
        O.ISIMPL,
        O.PROCEDURE_CODING__C,
        PRESCRIBER,
        SURGEON,
        PHYSICIAN
    FROM
        tmpOpps O
        LEFT JOIN sfdcAccount A ON O.ACT_ID = A.ID
    WHERE
        REASON_FOR_IMPLANT__C = 'De novo'
        AND INDICATION_FOR_USE__C = 'Heart Failure - Reduced Ejection Fraction'
),
IMPL AS (
    SELECT
        ACCOUNT_NAME,
        ACT_ID,
        SUM(
            CASE
                WHEN IMPLANTED_YYYYQQ <= @MINUS4Q THEN IMPLANT_UNITS
                ELSE 0
            END
        ) AS [-4Q_IMPL],
        SUM(
            CASE
                WHEN IMPLANTED_YYYYQQ <= @MINUS3Q THEN IMPLANT_UNITS
                ELSE 0
            END
        ) AS [-3Q_IMPL],
        SUM(
            CASE
                WHEN IMPLANTED_YYYYQQ <= @MINUS2Q THEN IMPLANT_UNITS
                ELSE 0
            END
        ) AS [-2Q_IMPL],
        SUM(
            CASE
                WHEN IMPLANTED_YYYYQQ <= @MINUS1Q THEN IMPLANT_UNITS
                ELSE 0
            END
        ) AS [-1Q_IMPL],
        SUM(
            CASE
                WHEN IMPLANTED_YYYYMM BETWEEN @MONTH_MINUS_6
                AND @MONTH_MINUS_1 THEN IMPLANT_UNITS
                ELSE 0
            END
        ) AS R6_IMPLANTS,
        AVG(
            CASE
                WHEN CREATED_YYYYMM BETWEEN @MONTH_MINUS_6
                AND @MONTH_MINUS_1
                AND IMPLANTED_YYYYMM BETWEEN @MONTH_MINUS_6
                AND @MONTH_MINUS_1
                AND TIME_TO_IMPL IS NOT NULL THEN TIME_TO_IMPL
            END
        ) AS R6_AVG_TIME_TO_IMPL,
        SUM(
            CASE
                WHEN PROCEDURE_CODING__C = 'In-Patient'
                AND IMPLANTED_YYYYMM BETWEEN @MONTH_MINUS_12
                AND @MONTH_MINUS_1 THEN 1
                ELSE 0
            END
        ) AS R12_INPATIENT_IMPL,
        SUM(
            CASE
                WHEN PROCEDURE_CODING__C = 'Out-Patient'
                AND IMPLANTED_YYYYMM BETWEEN @MONTH_MINUS_12
                AND @MONTH_MINUS_1 THEN 1
                ELSE 0
            END
        ) AS R12_OUTPATIENT_IMPL,
        SUM(
            CASE
                WHEN PROCEDURE_CODING__C = 'In-Patient'
                AND IMPLANTED_YYYYMM BETWEEN @MONTH_MINUS_24
                AND @MONTH_MINUS_13 THEN 1
                ELSE 0
            END
        ) AS PREV_R12_INPATIENT_IMPL,
        SUM(
            CASE
                WHEN PROCEDURE_CODING__C = 'Out-Patient'
                AND IMPLANTED_YYYYMM BETWEEN @MONTH_MINUS_24
                AND @MONTH_MINUS_13 THEN 1
                ELSE 0
            END
        ) AS PREV_R12_OUTPATIENT_IMPL
    FROM
        OPPS
    WHERE
        OPP_STATUS = 'CLOSED'
    GROUP BY
        ACCOUNT_NAME,
        ACT_ID
),
PATIENTS_IN_FUNNEL AS (
    SELECT
        ACT_ID,
        SUM(
            CASE
                WHEN CREATED_YYYYQQ = @MINUS4Q THEN 1
                ELSE 0
            END
        ) AS [-4Q_PATIENTS_IN_FUNNEL],
        SUM(
            CASE
                WHEN CREATED_YYYYQQ = @MINUS3Q THEN 1
                ELSE 0
            END
        ) AS [-3Q_PATIENTS_IN_FUNNEL],
        SUM(
            CASE
                WHEN CREATED_YYYYQQ = @MINUS2Q THEN 1
                ELSE 0
            END
        ) AS [-2Q_PATIENTS_IN_FUNNEL],
        SUM(
            CASE
                WHEN CREATED_YYYYQQ = @MINUS1Q THEN 1
                ELSE 0
            END
        ) AS [-1Q_PATIENTS_IN_FUNNEL],
        SUM(
            CASE
                WHEN CREATED_YYYYMM BETWEEN @MONTH_MINUS_6
                AND @MONTH_MINUS_1 THEN 1
                ELSE 0
            END
        ) AS [R6_PATIENTS_IN_FUNNEL]
    FROM
        OPPS
    GROUP BY
        ACT_ID
),
REF_PRES AS (
    SELECT
        ACT_ID,
        /* find distinct referrers and prescribers who have a patient with an implant */
        COUNT(
            DISTINCT CASE
                WHEN IMPLANTED_YYYYQQ = @MINUS4Q
                AND ISIMPL = 1
                AND OPP_STATUS = 'CLOSED' THEN PHYSICIAN_ID
            END
        ) AS [-4Q_REF_PRES],
        COUNT(
            DISTINCT CASE
                WHEN IMPLANTED_YYYYQQ = @MINUS3Q
                AND ISIMPL = 1
                AND OPP_STATUS = 'CLOSED' THEN PHYSICIAN_ID
            END
        ) AS [-3Q_REF_PRES],
        COUNT(
            DISTINCT CASE
                WHEN IMPLANTED_YYYYQQ = @MINUS2Q
                AND ISIMPL = 1
                AND OPP_STATUS = 'CLOSED' THEN PHYSICIAN_ID
            END
        ) AS [-2Q_REF_PRES],
        COUNT(
            DISTINCT CASE
                WHEN IMPLANTED_YYYYQQ = @MINUS1Q
                AND ISIMPL = 1
                AND OPP_STATUS = 'CLOSED' THEN PHYSICIAN_ID
            END
        ) AS [-1Q_REF_PRES],
        /* find ALL referrers and prescribers listed on opps created in the last 6 months */
        COUNT(
            DISTINCT CASE
                WHEN CREATED_YYYYMM BETWEEN @MONTH_MINUS_6
                AND @MONTH_MINUS_1 THEN PHYSICIAN_ID
            END
        ) AS [R6_REF_PRES (INCL NO IMPLANT)]
    FROM
        (
            SELECT
                ACT_ID,
                PHYSICIAN_ID,
                CREATEDDATE,
                CREATED_YYYYMM,
                CREATED_YYYYQQ,
                IMPLANTED_DT,
                IMPLANTED_YYYYMM,
                IMPLANTED_YYYYQQ,
                OPP_STATUS,
                ISIMPL,
                'REFERRER' AS [TYPE]
            FROM
                Opps A
            WHERE
                A.PHYSICIAN_ID IS NOT NULL
            UNION
            ALL
            SELECT
                ACT_ID,
                PRESCRIBER_ID,
                CREATEDDATE,
                CREATED_YYYYMM,
                CREATED_YYYYQQ,
                IMPLANTED_DT,
                IMPLANTED_YYYYMM,
                IMPLANTED_YYYYQQ,
                OPP_STATUS,
                ISIMPL,
                'PRESCRIBER'
            FROM
                Opps A
            WHERE
                A.PRESCRIBER_ID IS NOT NULL
        ) AS A
    GROUP BY
        ACT_ID
),
IMPLANTERS AS (
    SELECT
        ACT_ID,
        COUNT(
            DISTINCT CASE
                WHEN IMPLANTED_YYYYMM BETWEEN FORMAT(DATEADD(MONTH, -12, GETDATE()), 'yyyyMM')
                AND FORMAT(DATEADD(MONTH, -1, GETDATE()), 'yyyyMM') THEN SURGEON_ID
            END
        ) AS C12_IMPLANTERS,
        COUNT(
            DISTINCT CASE
                WHEN IMPLANTED_YYYYMM BETWEEN FORMAT(DATEADD(MONTH, -24, GETDATE()), 'yyyyMM')
                AND FORMAT(DATEADD(MONTH, -13, GETDATE()), 'yyyyMM') THEN SURGEON_ID
            END
        ) AS R12_IMPLANTERS
    FROM
        OPPS
    WHERE
        OPP_STATUS = 'CLOSED'
        AND ISIMPL = 1
        AND SURGEON_ID IS NOT NULL
    GROUP BY
        ACT_ID
),
CPAS AS (
    SELECT
        ACT_ID,
        ISNULL(
            SUM(
                CASE
                    WHEN SUBMIT_YYYYQQ = @MINUS1Q THEN 1
                    ELSE 0
                END
            ),
            0
        ) AS [-1Q_CPAS],
        ISNULL(
            SUM(
                CASE
                    WHEN SUBMIT_YYYYQQ = @MINUS2Q THEN 1
                    ELSE 0
                END
            ),
            0
        ) AS [-2Q_CPAS]
    FROM
        (
            SELECT
                *,
                CONCAT(
                    YEAR(EARLIEST_CPAS_PA_SUB_DT),
                    '_Q',
                    DATEPART(QUARTER, EARLIEST_CPAS_PA_SUB_DT)
                ) AS SUBMIT_YYYYQQ
            FROM
                (
                    SELECT
                        PAT_ID,
                        ACT_ID,
                        MIN(CASENUMBER) [FIRST],
                        MAX(CASENUMBER) [LAST],
                        MIN(CPAS_PA_SUB_DT) [EARLIEST_CPAS_PA_SUB_DT]
                    FROM
                        qryCPAS_Cases
                    WHERE
                        CPAS_PA_SUB_DT IS NOT NULL
                    GROUP BY
                        PAT_ID,
                        ACT_ID
                ) AS A
        ) AS B
    GROUP BY
        ACT_ID
)
SELECT
    IMPL.*,
    ISNULL(
        CAST(
            CAST(R12_INPATIENT_IMPL AS DECIMAL(10, 2)) / NULLIF(R12_INPATIENT_IMPL + R12_OUTPATIENT_IMPL, 0) AS DECIMAL(10, 2)
        ),
        0
    ) AS R12_IP_MIX,
    ISNULL(
        CAST(
            CAST(R12_OUTPATIENT_IMPL AS DECIMAL(10, 2)) / NULLIF(R12_INPATIENT_IMPL + R12_OUTPATIENT_IMPL, 0) AS DECIMAL(10, 2)
        ),
        0
    ) AS R12_OP_MIX,
    isnull(
        CAST(
            CAST(PREV_R12_INPATIENT_IMPL AS DECIMAL(10, 2)) / NULLIF(
                PREV_R12_INPATIENT_IMPL + PREV_R12_OUTPATIENT_IMPL,
                0
            ) AS DECIMAL(10, 2)
        ),
        0
    ) AS PREV_R12_IP_MIX,
    ISNULL(
        CAST(
            CAST(PREV_R12_OUTPATIENT_IMPL AS DECIMAL(10, 2)) / NULLIF(
                PREV_R12_INPATIENT_IMPL + PREV_R12_OUTPATIENT_IMPL,
                0
            ) AS DECIMAL(10, 2)
        ),
        0
    ) AS PREV_R12_OP_MIX,
    P.[-4Q_PATIENTS_IN_FUNNEL],
    P.[-3Q_PATIENTS_IN_FUNNEL],
    P.[-2Q_PATIENTS_IN_FUNNEL],
    P.[-1Q_PATIENTS_IN_FUNNEL],
    P.R6_PATIENTS_IN_FUNNEL,
    R.[-4Q_REF_PRES],
    R.[-3Q_REF_PRES],
    R.[-2Q_REF_PRES],
    R.[-1Q_REF_PRES],
    R.[R6_REF_PRES (INCL NO IMPLANT)],
    I.C12_IMPLANTERS,
    I.R12_IMPLANTERS,
    ISNULL(CPAS.[-1Q_CPAS], 0) [-1Q_CPAS],
    ISNULL(CPAS.[-2Q_CPAS], 0) [-2Q_CPAS],
    PR.CMS_ID,
    PR.[isProgram?_EX_CHAMP]
FROM
    IMPL
    LEFT JOIN PATIENTS_IN_FUNNEL P ON IMPL.ACT_ID = P.ACT_ID
    LEFT JOIN REF_PRES R ON IMPL.ACT_ID = R.ACT_ID
    LEFT JOIN IMPLANTERS I ON IMPL.ACT_ID = I.ACT_ID
    LEFT JOIN CPAS ON IMPL.ACT_ID = CPAS.ACT_ID
    LEFT JOIN tmpProgram_KPI PR ON IMPL.ACT_ID = PR.SFDC_ID -- WHERE
    --     PR.[isProgram?_EX_CHAMP] = 1
WHERE
    impl.ACT_ID IN (
        '0014u00001pyTz7AAE',
        '0014u00001pyTz5AAE',
        '0014u00001s9EvjAAE',
        '0017000001PgZDEAA3',
        '0017000001LsiQyAAJ',
        '001UY00000OYMQ9YAP',
        '0017000001Lsj5JAAR',
        '0017000001LsiwgAAB',
        '0010g00001kNUhOAAW',
        '0014u00001s9Em3AAE',
        '0010g00001XatwtAAB',
        '0017000001PgZD6AAN'
    )