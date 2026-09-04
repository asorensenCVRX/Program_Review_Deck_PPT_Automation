--MUST RUN setup_sql.sql FILE FIRST IN THE SAME CONNECTION IN THE .PY FILE
WITH CPAS0 AS (
    SELECT
        A.*,
        b.OPP_NAME,
        b.OPP_ID,
        b.isReplc_Case,
        b.RECORD_TYPE,
        b.CASE_ID [FIRST_ID],
        c.CASE_ID [LAST_ID],
        o.INDICATION_FOR_USE__C,
        o.REASON_FOR_IMPLANT__C,
        o.STAGENAME,
        CASE
            WHEN o.STAGENAME IN (
                'Revenue Recognized',
                'Procedure recognized',
                'Implant Completed'
            ) THEN 'Yes'
            ELSE 'No'
        END AS [isImplanted?],
        INSURANCE_MAIN,
        o.PROCEDURE_CODING__C,
        ISNULL(Primary_Insurance__c, INSURANCE_COMPANY_OTHER__C) AS MedicareAdv_SubType,
        isnull(o.ACT_OWNER_REGION, 'Other') ACT_OWNER_REGION,
        o.ACT_OWNER_NAME,
        o.ACCOUNT_INDICATION__C,
        O.ACT_ID,
        CASE
            WHEN C.CASE_STATUS = 'APPROVED' THEN datediff(
                dd,
                isnull(B.CPAS_PA_SUB_DT, a.EARLIEST_CPAS_PA_SUB_DT),
                C.CPAS_PA_APPROVAL_DT
            )
            ELSE NULL
        END AS [DAYS_TO_APPROVAL],
        GREATEST(
            CASE
                WHEN C.CASE_STATUS = 'APPROVED' THEN datediff(
                    dd,
                    isnull(B.CPAS_PA_SUB_DT, a.EARLIEST_CPAS_PA_SUB_DT),
                    C.CPAS_PA_APPROVAL_DT
                )
                WHEN C.CASE_STATUS IN ('DENIED', 'CANCELLED') THEN datediff(
                    dd,
                    isnull(
                        isnull(B.CPAS_PA_SUB_DT, a.EARLIEST_CPAS_PA_SUB_DT),
                        c.CREATED_DATE
                    ),
                    isnull(C.CPAS_PA_denial_DT, c.LATEST_STATUS_DATE__C)
                )
                WHEN C.CASE_STATUS = 'PENDING' THEN datediff(
                    dd,
                    isnull(
                        isnull(B.CPAS_PA_SUB_DT, a.EARLIEST_CPAS_PA_SUB_DT),
                        c.CREATED_DATE
                    ),
                    cast(getdate() AS DATE)
                )
                ELSE NULL
            END,
            0
        ) AS [DURATION],
        B.CPAS_PA_SUB_DT,
        isnull(B.CPAS_SUBMIT_YYYYMM, r.yyyyMM) CPAS_SUBMIT_YYYYMM,
        left(isnull(B.CPAS_SUBMIT_YYYYMM, r.yyyyMM), 4) CPAS_SUBMIT_YYYY,
        C.CPAS_PA_APPROVAL_DT,
        c.CPAS_PA_DENIAL_DT,
        C.CREATED_DATE,
        c.LATEST_STATUS_DATE__C,
        c.STATUS,
        C.[isExcl?],
        C.[isExclV2?],
        c.SUB_STATUS__C,
        CASE
            WHEN c.SUB_STATUS__C = 'APPROVED'
            AND isnull(B.CPAS_PA_SUB_DT, a.EARLIEST_CPAS_PA_SUB_DT) IS NULL THEN 'APPROVED WITH NO SUBMIT DATE'
            WHEN c.SUB_STATUS__C = 'APPROVED'
            AND c.CPAS_PA_DENIAL_DT IS NOT NULL
            AND C.CPAS_PA_APPROVAL_DT IS NULL THEN 'APPROVED WITH DENIAL DATE'
            WHEN c.SUB_STATUS__C = 'APPROVED'
            AND c.CPAS_PA_APPROVAL_DT IS NULL THEN 'APPROVED WITH NO APPROVAL DATE'
            WHEN isnull(
                (
                    CASE
                        WHEN b.OPP_NAME IS NOT NULL THEN COUNT(b.OPP_NAME) OVER (PARTITION BY b.OPP_NAME)
                        ELSE NULL
                    END
                ),
                1
            ) > 1 THEN 'DUPLICATE PATIENT SORT BY OPP'
        END AS [ANAMOLY],
        c.[CASE_STATUS],
        CASE
            WHEN c.CASE_STATUS = 'APPROVED' THEN 1
            ELSE 0
        END AS [APPROVED],
        CASE
            WHEN c.CASE_STATUS = 'Pending' THEN 1
            ELSE 0
        END AS [PENDING],
        CASE
            WHEN c.CASE_STATUS NOT IN ('Pending', 'Approved') THEN 1
            ELSE 0
        END AS [CLOSED],
        1 AS [COUNTER]
    FROM
        /*****************
         
         **************/
        #temp2 AS A
        LEFT JOIN #temp B
        ON a.[FIRST] = b.CASENUMBER
        LEFT JOIN #temp C
        ON a.[LAST] = C.CASENUMBER
        LEFT JOIN qryCalendar R ON r.DT = a.EARLIEST_CPAS_PA_SUB_DT
        LEFT JOIN tmpOpps O ON isnull(b.OPP_ID, c.OPP_ID) = o.OPP_ID
),
-- --    ,
--  select * from Cases_other
-- --3633
--3893 -- no filter at all 
--3610 for filter = 1 
--283 for filter = 0 
CPAS1 AS (
    SELECT
        T.*,
        CASE
            WHEN DAYS_TO_APPROVAL BETWEEN 0
            AND 30 THEN '0 to 30 Days'
            WHEN DAYS_TO_APPROVAL BETWEEN 31
            AND 60 THEN '31 to 60 Days'
            WHEN DAYS_TO_APPROVAL BETWEEN 61
            AND 90 THEN '61 to 90 Days'
            WHEN DAYS_TO_APPROVAL > 90 THEN '91+ Days'
            ELSE NULL
        END AS [APPROVAL_BIN],
        CASE
            WHEN CASE_STATUS = 'PENDING'
            AND [DURATION] < 7 THEN 'EXCLUDE_TOO_NEW'
            WHEN CASE_STATUS = 'APPROVED'
            AND [DURATION] BETWEEN 0
            AND 7 THEN 'APPROVED'
            WHEN CASE_STATUS = 'DENIED'
            AND [DURATION] BETWEEN 0
            AND 7 THEN 'DENIED'
            WHEN CASE_STATUS = 'CANCELLED'
            AND [DURATION] BETWEEN 0
            AND 7 THEN 'CANCELLED'
            ELSE 'PENDING'
        END AS [DAY_7],
        CASE
            WHEN CASE_STATUS = 'PENDING'
            AND [DURATION] < 15 THEN 'EXCLUDE_TOO_NEW'
            WHEN CASE_STATUS = 'APPROVED'
            AND [DURATION] BETWEEN 0
            AND 15 THEN 'APPROVED'
            WHEN CASE_STATUS = 'DENIED'
            AND [DURATION] BETWEEN 0
            AND 15 THEN 'DENIED'
            WHEN CASE_STATUS = 'CANCELLED'
            AND [DURATION] BETWEEN 0
            AND 15 THEN 'CANCELLED'
            ELSE 'PENDING'
        END AS [DAY_15],
        CASE
            WHEN CASE_STATUS = 'PENDING'
            AND [DURATION] < 30 THEN 'EXCLUDE_TOO_NEW'
            WHEN CASE_STATUS = 'APPROVED'
            AND [DURATION] BETWEEN 0
            AND 30 THEN 'APPROVED'
            WHEN CASE_STATUS = 'DENIED'
            AND [DURATION] BETWEEN 0
            AND 30 THEN 'DENIED'
            WHEN CASE_STATUS = 'CANCELLED'
            AND [DURATION] BETWEEN 0
            AND 30 THEN 'CANCELLED'
            ELSE 'PENDING'
        END AS [DAY_30],
        CASE
            WHEN CASE_STATUS = 'PENDING'
            AND [DURATION] < 60 THEN 'EXCLUDE_TOO_NEW'
            WHEN CASE_STATUS = 'APPROVED'
            AND [DURATION] BETWEEN 0
            AND 60 THEN 'APPROVED'
            WHEN CASE_STATUS = 'DENIED'
            AND [DURATION] BETWEEN 0
            AND 60 THEN 'DENIED'
            WHEN CASE_STATUS = 'CANCELLED'
            AND [DURATION] BETWEEN 0
            AND 60 THEN 'CANCELLED'
            ELSE 'PENDING'
        END AS [DAY_60],
        CASE
            WHEN CASE_STATUS = 'PENDING'
            AND [DURATION] < 90 THEN 'EXCLUDE_TOO_NEW'
            WHEN CASE_STATUS = 'APPROVED'
            AND [DURATION] BETWEEN 0
            AND 90 THEN 'APPROVED'
            WHEN CASE_STATUS = 'DENIED'
            AND [DURATION] BETWEEN 0
            AND 90 THEN 'DENIED'
            WHEN CASE_STATUS = 'CANCELLED'
            AND [DURATION] BETWEEN 0
            AND 90 THEN 'CANCELLED'
            ELSE 'PENDING'
        END AS [DAY_90],
        CASE
            WHEN CASE_STATUS = 'PENDING'
            AND [DURATION] < 120 THEN 'EXCLUDE_TOO_NEW'
            WHEN CASE_STATUS = 'APPROVED'
            AND [DURATION] BETWEEN 0
            AND 120 THEN 'APPROVED'
            WHEN CASE_STATUS = 'DENIED'
            AND [DURATION] BETWEEN 0
            AND 120 THEN 'DENIED'
            WHEN CASE_STATUS = 'CANCELLED'
            AND [DURATION] BETWEEN 0
            AND 120 THEN 'CANCELLED'
            ELSE 'PENDING'
        END AS [DAY_120]
    FROM
        CPAS0 AS T
),
CAL AS (
    SELECT
        DISTINCT r3,
        r6,
        r12,
        yyyymm
    FROM
        qrycalendar
    WHERE
        r12 IS NOT NULL
),
EXP AS (
    SELECT
        CPAS1.*,
        m.yyyyqq AS [CPAS_SUBMIT_YYYYQQ],
        r3,
        r6,
        r12,
        CASE
            WHEN R3 = 'C3' THEN 1
            ELSE 0
        END AS [C3],
        CASE
            WHEN R3 = 'P3' THEN 1
            ELSE 0
        END AS [P3],
        CASE
            WHEN R6 = 'C6' THEN 1
            ELSE 0
        END AS [C6],
        CASE
            WHEN R6 = 'P6' THEN 1
            ELSE 0
        END AS [P6],
        CASE
            WHEN R12 = 'C12' THEN 1
            ELSE 0
        END AS [C12],
        CASE
            WHEN R12 = 'P12' THEN 1
            ELSE 0
        END AS [P12],
        D.[%_COMPLETE],
        isnull(D.[%_COMPLETE], 0) * [COUNTER] AS [PY_YTD],
        CASE
            WHEN CPAS_SUBMIT_YYYY = datepart(yyyy, getdate()) THEN counter
        END AS [CY_YTD],
        ACCOUNT_INDICATION__C + ' - ' + ACT_OWNER_REGION [ACT_W_REGION],
        CASE
            WHEN CPAS_SUBMIT_YYYYMM < FORMAT(DATEADD(DAY, - 60, GETDATE()), 'yyyy_MM') THEN 1
            ELSE 0
        END AS [INCLUDE_IN_SUM?],
        CASE
            WHEN DAY_15 = 'APPROVED' THEN 'A'
            WHEN DAY_15 = 'PENDING' THEN 'B'
            WHEN DAY_15 = 'DENIED' THEN 'C'
            ELSE 'D'
        END AS DAY_15_SORT,
        CASE
            WHEN DAY_30 = 'APPROVED' THEN 'A'
            WHEN DAY_30 = 'PENDING' THEN 'B'
            WHEN DAY_30 = 'DENIED' THEN 'C'
            ELSE 'D'
        END AS DAY_30_SORT,
        CASE
            WHEN DAY_60 = 'APPROVED' THEN 'A'
            WHEN DAY_60 = 'PENDING' THEN 'B'
            WHEN DAY_60 = 'DENIED' THEN 'C'
            ELSE 'D'
        END AS DAY_60_SORT,
        CASE
            WHEN DAY_90 = 'APPROVED' THEN 'A'
            WHEN DAY_90 = 'PENDING' THEN 'B'
            WHEN DAY_90 = 'DENIED' THEN 'C'
            ELSE 'D'
        END AS DAY_90_SORT,
        CASE
            WHEN DAY_120 = 'APPROVED' THEN 'A'
            WHEN DAY_120 = 'PENDING' THEN 'B'
            WHEN DAY_120 = 'DENIED' THEN 'C'
            ELSE 'D'
        END AS DAY_120_SORT
    FROM
        CPAS1
        LEFT JOIN CAL ON CPAS1.CPAS_SUBMIT_YYYYMM = CAL.YYYYMM
        LEFT JOIN qryCalendar_To_DT D ON CPAS1.CPAS_SUBMIT_YYYYMM = D.yyyymm_PY
        LEFT JOIN (
            SELECT
                DISTINCT YYYYMM,
                YYYYQQ
            FROM
                qrycalendar
        ) AS M ON cpas1.CPAS_SUBMIT_YYYYMM = m.yyyyMM -- WHERE
        --     INSURANCE_MAIN IN ('Medicare Advantage', 'Commercial')
        --     AND CPAS_SUBMIT_YYYYMM < FORMAT(DATEADD(DAY, -60, GETDATE()), 'yyyy_MM')
),
TIME AS (
    SELECT
        TRY_CAST(
            LEFT(CENTRAL, CHARINDEX(' out of ', CENTRAL) - 1) AS INT
        ) AS DaysElapsed,
        TRY_CAST(
            SUBSTRING(
                CENTRAL,
                CHARINDEX('out of ', CENTRAL) + 7,
                CHARINDEX(' Billing', CENTRAL) - (CHARINDEX('out of ', CENTRAL) + 7)
            ) AS INT
        ) AS DaysInMonth
    FROM
        qryTimeStamp
    WHERE
        [ROW] = 2
),
exp1 AS (
    SELECT
        *,
        (
            SELECT
                (
                    (
                        (
                            (count(*) * 1.00) / (
                                (
                                    SELECT
                                        dayselapsed
                                    FROM
                                        TIME
                                ) * 1.00
                            )
                        ) * (
                            SELECT
                                daysinmonth
                            FROM
                                TIME
                        ) * 1.00
                    )
                )
            FROM
                EXP
            WHERE
                [isexcl?] = 0
                AND CPAS_SUBMIT_YYYYMM = (
                    SELECT
                        DISTINCT YYYYMM
                    FROM
                        qrycalendar
                    WHERE
                        DT = cast(dateadd(hh, - 5, getdate()) AS DATE)
                )
                AND (
                    isnull(CPAS_PA_SUB_DT, EARLIEST_CPAS_PA_SUB_DT) < (cast(dateadd(hh, - 5, getdate()) AS DATE))
                    OR isnull(CPAS_PA_SUB_DT, EARLIEST_CPAS_PA_SUB_DT) IS NULL
                )
        ) AS [RR_CM]
    FROM
        EXP
),
Q AS (
    SELECT
        -- 'https://cvrx.lightning.force.com/lightning/r/Patient__c/' + [PATIENT__C] + '/view' AS [PATIENT_URL],
        -- [PATIENT__C],
        -- [FIRST],
        -- 'https://cvrx.lightning.force.com/lightning/r/Case/' + FIRST_ID + '/view' [FIRST_CASE_URL],
        -- [LAST],
        -- 'https://cvrx.lightning.force.com/lightning/r/Case/' + LAST_ID + '/view' [LAST_CASE_URL],
        -- [OPP_ID],
        -- 'https://cvrx.lightning.force.com/lightning/r/Opportunity/' + OPP_ID + '/view' [OPP_URL],
        [EARLIEST_CPAS_PA_SUB_DT],
        [totalcases],
        [Key],
        -- [REASON_FOR_IMPLANT],
        -- CASE
        --     WHEN REASON_FOR_IMPLANT = 'OTHER'
        --     AND RECORD_TYPE <> 'Commercial' THEN 'Trial Patient'
        --     WHEN REASON_FOR_IMPLANT = 'OTHER'
        --     AND INDICATION_FOR_USE__C = 'Heart Failure - Reduced Ejection Fraction' THEN 'Submitted Post Implant'
        --     WHEN REASON_FOR_IMPLANT = 'OTHER'
        --     AND INDICATION_FOR_USE__C = 'Hypertension' THEN 'Hypertension'
        --     WHEN REASON_FOR_IMPLANT = 'OTHER' THEN 'Data Issue'
        --     ELSE NULL
        -- END AS [Exception],
        [OPP_NAME],
        OPP_ID,
        -- [isReplc_Case],
        -- [RECORD_TYPE],
        [INDICATION_FOR_USE__C],
        [REASON_FOR_IMPLANT__C],
        [STAGENAME],
        [isImplanted?],
        [INSURANCE_MAIN],
        [PROCEDURE_CODING__C],
        [MedicareAdv_SubType],
        -- [ACT_OWNER_REGION],
        -- [ACT_OWNER_NAME],
        [ACCOUNT_INDICATION__C],
        [ACT_ID],
        [DAYS_TO_APPROVAL],
        [DURATION],
        [CPAS_PA_SUB_DT],
        [CPAS_SUBMIT_YYYYMM],
        [CPAS_SUBMIT_YYYY],
        [CPAS_PA_APPROVAL_DT],
        [CPAS_PA_DENIAL_DT],
        [CREATED_DATE],
        [LATEST_STATUS_DATE__C],
        [STATUS],
        [isExcl?],
        [isExclV2?],
        [SUB_STATUS__C],
        [ANAMOLY],
        [CASE_STATUS],
        [APPROVED],
        [PENDING],
        [CLOSED],
        [COUNTER],
        [APPROVAL_BIN],
        [DAY_7],
        [DAY_15],
        [DAY_30],
        [DAY_60],
        [DAY_90],
        [DAY_120],
        [CPAS_SUBMIT_YYYYQQ],
        [R3],
        [R6],
        [R12],
        [C3],
        [P3],
        [C6],
        [P6],
        [C12],
        [P12],
        [%_COMPLETE],
        [PY_YTD],
        [CY_YTD],
        [ACT_W_REGION],
        [INCLUDE_IN_SUM?],
        [DAY_15_SORT],
        [DAY_30_SORT],
        [DAY_60_SORT],
        [DAY_90_SORT],
        [DAY_120_SORT],
        [RR_CM],
        CASE
            WHEN CPAS_SUBMIT_YYYYMM = (
                SELECT
                    DISTINCT YYYYMM
                FROM
                    qrycalendar
                WHERE
                    DT = cast(dateadd(hh, - 5, getdate()) AS DATE)
            ) THEN [RR_CM]
            WHEN CPAS_SUBMIT_YYYYMM = (
                SELECT
                    DISTINCT YYYYMM
                FROM
                    qrycalendar
                WHERE
                    DT = cast(dateadd(mm, - 1, getdate()) AS DATE)
            ) THEN (
                SELECT
                    count(*)
                FROM
                    EXP
                WHERE
                    [isexcl?] = 0
                    AND CPAS_SUBMIT_YYYYMM = (
                        SELECT
                            DISTINCT YYYYMM
                        FROM
                            qrycalendar
                        WHERE
                            DT = cast(dateadd(mm, - 1, getdate()) AS DATE)
                    )
            )
            ELSE NULL
        END AS [RR_CM_V2],
        CASE
            WHEN CASE_STATUS = 'PENDING' THEN 'PENDING'
            WHEN CASE_STATUS = 'APPROVED' THEN 'APPROVED'
            ELSE 'CLOSED'
        END AS CASE_STATUS_V2,
        CASE
            WHEN [CPAS_PA_SUB_DT] < DATEADD(DAY, -7, CAST(GETDATE() AS DATE)) THEN 0
            ELSE 1
        END AS [LESS_THAN_7_DAYS?],
        CASE
            WHEN [CPAS_PA_SUB_DT] < DATEADD(DAY, -15, CAST(GETDATE() AS DATE)) THEN 0
            ELSE 1
        END AS [LESS_THAN_15_DAYS?],
        CASE
            WHEN [CPAS_PA_SUB_DT] < DATEADD(DAY, -30, CAST(GETDATE() AS DATE)) THEN 0
            ELSE 1
        END AS [LESS_THAN_30_DAYS?],
        CASE
            WHEN [CPAS_PA_SUB_DT] < DATEADD(DAY, -60, CAST(GETDATE() AS DATE)) THEN 0
            ELSE 1
        END AS [LESS_THAN_60_DAYS?],
        CASE
            WHEN [CPAS_PA_SUB_DT] < DATEADD(DAY, -90, CAST(GETDATE() AS DATE)) THEN 0
            ELSE 1
        END AS [LESS_THAN_90_DAYS?],
        CASE
            WHEN [CPAS_PA_SUB_DT] < DATEADD(DAY, -120, CAST(GETDATE() AS DATE)) THEN 0
            ELSE 1
        END AS [LESS_THAN_120_DAYS?]
    FROM
        exp1
),
Q2 AS (
    SELECT
        ACT_ID,
        ACCOUNT_INDICATION__C,
        OPP_NAME,
        CPAS_SUBMIT_YYYYQQ,
        CASE
            WHEN CPAS_SUBMIT_YYYYQQ = CONCAT(
                YEAR(DATEADD(QUARTER, -1, GETDATE())),
                '_Q',
                DATEPART(QUARTER, DATEADD(QUARTER, -1, GETDATE()))
            ) THEN 1
            ELSE 0
        END AS [-1Q_SUBMIT],
        CASE
            WHEN CPAS_SUBMIT_YYYYQQ BETWEEN CONCAT(
                YEAR(DATEADD(QUARTER, -4, GETDATE())),
                '_Q',
                DATEPART(QUARTER, DATEADD(QUARTER, -4, GETDATE()))
            )
            AND CONCAT(
                YEAR(DATEADD(QUARTER, -1, GETDATE())),
                '_Q',
                DATEPART(QUARTER, DATEADD(QUARTER, -1, GETDATE()))
            ) THEN 1
            ELSE 0
        END AS [-4Q_SUBMIT],
        INSURANCE_MAIN,
        REPLACE(
            REPLACE(
                MedicareAdv_SubType,
                'Medicare Advantage',
                'Med Adv.'
            ),
            'Medicare',
            'Med Adv.'
        ) AS MedicareAdv_SubType,
        CASE_STATUS,
        DAY_30
    FROM
        Q
    WHERE
        [isExclV2?] = 0
        AND MedicareAdv_SubType IS NOT NULL
        AND INSURANCE_MAIN = 'Medicare Advantage'
        AND [LESS_THAN_30_DAYS?] = 0
        AND DAY_30 <> 'EXCLUDE_TOO_NEW'
),
Q3 AS (
    SELECT
        ACT_ID,
        MedicareAdv_SubType,
        SUM(
            CASE
                WHEN [-1Q_SUBMIT] = 1
                AND DAY_30 = 'APPROVED' THEN 1
                ELSE 0
            END
        ) * 1.0 / NULLIF(SUM([-1Q_SUBMIT]), 0) * 1.0 AS [-1Q_DAY_30_APPROVAL],
        SUM([-1Q_SUBMIT]) AS [-1Q_ELIGIBLE_SUBMISSIONS],
        SUM(
            CASE
                WHEN [-4Q_SUBMIT] = 1
                AND DAY_30 = 'APPROVED' THEN 1
                ELSE 0
            END
        ) * 1.0 / NULLIF(SUM([-4Q_SUBMIT]), 0) * 1.0 AS [R4Q_DAY_30_APPROVAL],
        SUM([-4Q_SUBMIT]) AS [R4Q_ELIGIBLE_SUBMISSIONS]
    FROM
        Q2
    GROUP BY
        ACT_ID,
        MedicareAdv_SubType
)
SELECT
    *
FROM
    (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY ACT_ID
                ORDER BY
                    [-1Q_ELIGIBLE_SUBMISSIONS] DESC,
                    [R4Q_ELIGIBLE_SUBMISSIONS] DESC
            ) AS RN
        FROM
            Q3
        WHERE
            (
                [-1Q_DAY_30_APPROVAL] IS NOT NULL
                OR R4Q_DAY_30_APPROVAL IS NOT NULL
            )
    ) AS A
WHERE
    RN <= 5