DECLARE @MONTH_MINUS_1 AS VARCHAR(7) = FORMAT(DATEADD(MONTH, -1, GETDATE()), 'yyyy_MM'),
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
        PHYSICIAN,
        P.[STATUS]
    FROM
        tmpOpps O
        LEFT JOIN sfdcAccount A ON O.ACT_ID = A.ID
        LEFT JOIN tmpProgram_KPI P ON O.ACT_ID = P.SFDC_ID
    WHERE
        REASON_FOR_IMPLANT__C = 'De novo'
        AND INDICATION_FOR_USE__C = 'Heart Failure - Reduced Ejection Fraction'
        AND P.STATUS IN ('At-Risk', 'Active', 'Dormant')
),
REF_PRES AS (
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
        ISIMPL
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
        ISIMPL
    FROM
        Opps A
    WHERE
        A.PRESCRIBER_ID IS NOT NULL
),
R6_REF_PRES AS (
    SELECT
        CAST(
            CEILING(AVG(CAST(R6_REF_PRES AS DECIMAL(18, 2)))) AS INT
        ) AS R6_REF_PRES
    FROM
        (
            SELECT
                TOP (5) PERCENT WITH TIES COUNT(DISTINCT PHYSICIAN_ID) R6_REF_PRES
            FROM
                REF_PRES
            WHERE
                CREATED_YYYYMM BETWEEN @MONTH_MINUS_6
                AND @MONTH_MINUS_1
            GROUP BY
                ACT_ID
            ORDER BY
                COUNT(DISTINCT PHYSICIAN_ID) DESC
        ) AS A
),
R6_OPPS_CREATED AS (
    SELECT
        CAST(
            CEILING(AVG(CAST(R6_OPPS_CREATED AS DECIMAL(18, 2)))) AS INT
        ) AS R6_OPPS_CREATED
    FROM
        (
            SELECT
                TOP (5) PERCENT WITH TIES COUNT(*) R6_OPPS_CREATED
            FROM
                OPPS
            WHERE
                CREATED_YYYYMM BETWEEN @MONTH_MINUS_6
                AND @MONTH_MINUS_1
            GROUP BY
                ACT_ID
            ORDER BY
                COUNT(*) DESC
        ) AS A
),
R6_AVG_TIME_TO_IMPL AS (
    SELECT
        CAST(CEILING(AVG(R6_TIME_TO_IMPL)) AS INT) AS R6_AVG_TIME_TO_IMPL
    FROM
        (
            SELECT
                TOP (5) PERCENT WITH TIES AVG(CAST(TIME_TO_IMPL AS DECIMAL(18, 2))) AS R6_TIME_TO_IMPL
            FROM
                OPPS
            WHERE
                ISIMPL = 1
                AND OPP_STATUS = 'CLOSED'
                AND CREATED_YYYYMM BETWEEN @MONTH_MINUS_6
                AND @MONTH_MINUS_1
                AND CREATEDDATE <= IMPLANTED_DT
            GROUP BY
                ACT_ID
            HAVING
                AVG(TIME_TO_IMPL) <> 0
            ORDER BY
                AVG(TIME_TO_IMPL) ASC
        ) AS A
),
R6_IMPL AS (
    SELECT
        CAST(
            CEILING(AVG(CAST(R6_IMPL AS decimal(18, 2)))) AS INT
        ) AS R6_IMPL_VOL
    FROM
        (
            SELECT
                TOP (5) PERCENT WITH TIES COUNT(*) AS R6_IMPL
            FROM
                OPPS
            WHERE
                ISIMPL = 1
                AND OPP_STATUS = 'CLOSED'
                AND IMPLANTED_YYYYMM BETWEEN @MONTH_MINUS_6
                AND @MONTH_MINUS_1
            GROUP BY
                ACT_ID
            ORDER BY
                COUNT(*) DESC
        ) AS A
)
SELECT
    *
FROM
    R6_REF_PRES
    CROSS JOIN R6_OPPS_CREATED
    CROSS JOIN R6_AVG_TIME_TO_IMPL
    CROSS JOIN R6_IMPL