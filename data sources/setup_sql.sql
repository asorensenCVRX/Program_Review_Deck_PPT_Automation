SET
    NOCOUNT ON;

DROP TABLE IF EXISTS #temp;
DROP TABLE IF EXISTS #temp2;
SELECT
    *,
    CASE
        WHEN REASON_FOR_IMPLANT__C = 'De Novo'
        AND INDICATION_FOR_USE__C = 'Heart Failure - Reduced Ejection Fraction'
        AND record_type = 'Commercial'
        AND isreplc_case = 0 THEN 1
        ELSE 0
    END AS [filter_denovo],
    CASE
        WHEN REASON_FOR_IMPLANT__C = 'Replacement'
        AND INDICATION_FOR_USE__C = 'Heart Failure - Reduced Ejection Fraction'
        AND record_type = 'Commercial'
        AND isreplc_case = 0 THEN 1
        ELSE 0
    END AS [filter_replc] INTO #temp
FROM
    qryCPAS_Cases
WHERE
    PATIENT__C NOT IN (
        SELECT
            P.ID
        FROM
            sfdcPatient P
            LEFT JOIN sfdcUser U ON P.CreatedById = u.id
        WHERE
            LAST_NAME_ENC2__C = 'TEST'
    );

/***********
 STAGE 1.5
 ***********/
WITH Cases_denovo AS (
    SELECT
        *
    FROM
        #temp
    WHERE
        [filter_denovo] = 1
),
Cases_replc AS (
    SELECT
        *
    FROM
        #temp
    WHERE
        [filter_replc] = 1
),
Cases_other AS (
    SELECT
        *
    FROM
        #temp
    WHERE
        [filter_replc] = 0
        AND filter_denovo = 0
)
SELECT
    * INTO #temp2
FROM
    (
        SELECT
            PATIENT__C,
            MIN(CASENUMBER) [FIRST],
            MAX(CASENUMBER) [LAST],
            MIN(a.CPAS_PA_SUB_DT) [EARLIEST_CPAS_PA_SUB_DT],
            Count(CASENUMBER) totalcases,
            'De Novo' AS [REASON_FOR_IMPLANT],
            PATIENT__C + '_D' [Key]
        FROM
            Cases_denovo A
        GROUP BY
            PATIENT__C
        UNION
        ALL
        SELECT
            PATIENT__C,
            MIN(CASENUMBER) [FIRST],
            MAX(CASENUMBER) [LAST],
            MIN(a.CPAS_PA_SUB_DT) [EARLIEST_CPAS_PA_SUB_DT],
            Count(CASENUMBER) totalcases,
            'Replacement' AS [REASON_FOR_IMPLANT],
            PATIENT__C + '_R' [Key]
        FROM
            Cases_replc A
        GROUP BY
            PATIENT__C
        UNION
        ALL
        SELECT
            PATIENT__C,
            MIN(CASENUMBER) [FIRST],
            MAX(CASENUMBER) [LAST],
            MIN(a.CPAS_PA_SUB_DT) [EARLIEST_CPAS_PA_SUB_DT],
            Count(CASENUMBER) totalcases,
            'Other' AS [REASON_FOR_IMPLANT],
            PATIENT__C + '_O' [Key]
        FROM
            Cases_Other A
        GROUP BY
            PATIENT__C
    ) AS t;