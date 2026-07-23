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
);

WITH OPPS AS (
    SELECT
        O.CREATEDDATE,
        O.CREATED_YYYYQQ,
        O.CLOSEDATE,
        O.CLOSE_YYYYMM,
        O.CLOSE_YYYYQQ,
        O.IMPLANTED_DT,
        O.IMPLANTED_YYYYMM,
        O.IMPLANTED_YYYYQQ,
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
REF_PRES AS (
    SELECT
        ACT_ID,
        OPP_ID,
        PHYSICIAN AS PHYSICIAN,
        CREATED_YYYYQQ,
        IMPLANTED_YYYYQQ,
        ISIMPL,
        OPP_STATUS
    FROM
        OPPS
    WHERE
        PHYSICIAN IS NOT NULL
    UNION
    SELECT
        ACT_ID,
        OPP_ID,
        PRESCRIBER,
        CREATED_YYYYQQ,
        IMPLANTED_YYYYQQ,
        ISIMPL,
        OPP_STATUS
    FROM
        OPPS
    WHERE
        PRESCRIBER IS NOT NULL
),
SURG AS (
    SELECT
        ACT_ID,
        SURGEON,
        SUM(
            CASE
                WHEN IMPLANTED_YYYYQQ = @MINUS1Q THEN 1
                ELSE 0
            END
        ) AS MINUS_1_Q_IMPLANTS,
        CAST(
            SUM(
                CASE
                    WHEN IMPLANTED_YYYYQQ IN (@MINUS1Q, @MINUS2Q, @MINUS3Q, @MINUS4Q) THEN 1
                    ELSE 0
                END
            ) / 4.0 AS DECIMAL(18, 1)
        ) AS QTLY_AVG_PAT_IMPLANTED,
        SUM(
            CASE
                WHEN IMPLANTED_YYYYQQ IN (@MINUS1Q, @MINUS2Q, @MINUS3Q, @MINUS4Q) THEN 1
                ELSE 0
            END
        ) AS LAST_4_Q_IMPLANTS,
        COUNT(*) AS TOTAL_IMPLANTS
    FROM
        (
            SELECT
                ACT_ID,
                OPP_ID,
                SURGEON,
                CREATED_YYYYQQ,
                IMPLANTED_YYYYQQ,
                ISIMPL,
                OPP_STATUS
            FROM
                OPPS
            WHERE
                SURGEON IS NOT NULL
                AND OPP_STATUS = 'CLOSED'
                AND ISIMPL = 1
        ) AS A
    GROUP BY
        ACT_ID,
        SURGEON
),
Z AS (
    SELECT
        ACT_ID,
        [PHYSICIAN],
        COUNT(*) AS TOTAL_PAT_IDENTIFIED,
        SUM(
            CASE
                WHEN CREATED_YYYYQQ = @MINUS1Q THEN 1
                ELSE 0
            END
        ) AS [-1Q_PAT_IDENTIFIED],
        SUM(
            CASE
                WHEN CREATED_YYYYQQ IN (@MINUS1Q, @MINUS2Q, @MINUS3Q, @MINUS4Q) THEN 1
                ELSE 0
            END
        ) / 4.0 AS [QTLY_AVG_PAT_IDENTIFIED],
        SUM(
            CASE
                WHEN ISIMPL = 1
                AND OPP_STATUS = 'CLOSED' THEN 1
                ELSE 0
            END
        ) AS TTL_IMPL,
        SUM(
            CASE
                WHEN ISIMPL = 1
                AND OPP_STATUS = 'CLOSED'
                AND IMPLANTED_YYYYQQ = @MINUS1Q THEN 1
                ELSE 0
            END
        ) AS [-1Q_PATS_IMPL],
        SUM(
            CASE
                WHEN ISIMPL = 1
                AND OPP_STATUS = 'CLOSED'
                AND IMPLANTED_YYYYQQ IN (@MINUS1Q, @MINUS2Q, @MINUS3Q, @MINUS4Q) THEN 1
                ELSE 0
            END
        ) / 4.0 AS QTLY_AVG_PAT_IMPLANTED,
        SUM(
            CASE
                WHEN ISIMPL = 1
                AND OPP_STATUS = 'CLOSED'
                AND IMPLANTED_YYYYQQ IN (@MINUS1Q, @MINUS2Q, @MINUS3Q, @MINUS4Q) THEN 1
                ELSE 0
            END
        ) AS LAST_4_Q_IMPLANTS
    FROM
        REF_PRES
    GROUP BY
        ACT_ID,
        [PHYSICIAN]
),
Z2 AS (
    SELECT
        *,
        'REF/PRES' AS DATASET
    FROM
        (
            SELECT
                *,
                ROW_NUMBER() OVER (
                    PARTITION BY ACT_ID
                    ORDER BY
                        [-1Q_PATS_IMPL] DESC,
                        TTL_IMPL DESC
                ) AS RN
            FROM
                Z
        ) AS A
    WHERE
        RN <= 8
        AND LAST_4_Q_IMPLANTS > 0
    UNION
    ALL
    SELECT
        ACT_ID,
        SURGEON,
        NULL,
        NULL,
        NULL,
        TOTAL_IMPLANTS,
        MINUS_1_Q_IMPLANTS,
        QTLY_AVG_PAT_IMPLANTED,
        LAST_4_Q_IMPLANTS,
        RN,
        'IMPLANTER'
    FROM
        (
            SELECT
                *,
                ROW_NUMBER() OVER (
                    PARTITION BY ACT_ID
                    ORDER BY
                        MINUS_1_Q_IMPLANTS DESC,
                        TOTAL_IMPLANTS DESC
                ) AS RN
            FROM
                SURG
        ) AS B
    WHERE
        RN <= 2
        AND LAST_4_Q_IMPLANTS > 0
)
SELECT
    ACT_ID,
    PHYSICIAN,
    TOTAL_PAT_IDENTIFIED,
    [-1Q_PAT_IDENTIFIED],
    CAST(QTLY_AVG_PAT_IDENTIFIED AS DECIMAL(18, 1)) AS QTLY_AVG_PAT_IDENTIFIED,
    TTL_IMPL,
    [-1Q_PATS_IMPL],
    CAST(QTLY_AVG_PAT_IMPLANTED AS DECIMAL(18, 1)) AS QTLY_AVG_PAT_IMPLANTED,
    LAST_4_Q_IMPLANTS,
    RN,
    DATASET
FROM
    Z2
ORDER BY
    RN