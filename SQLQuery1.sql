USE project_database;

--- 1. ETL AND CLEANING

CREATE TABLE Cleaned_UserBehavior (
    uid INT,
    pid INT,
    cat_id INT,
    behavior_type INT, 
    [datetime] DATETIME2,
    [date] DATE,
    [hour] INT
);

INSERT INTO Cleaned_UserBehavior (uid, pid, cat_id, behavior_type, [datetime], [date], [hour])
SELECT 
    column1 AS uid,
    column2 AS pid,
    column3 AS cat_id,
    CASE 
        WHEN column4 = 'pv' THEN 0
        WHEN column4 = 'fav' THEN 1
        WHEN column4 = 'cart' THEN 2
        WHEN column4 = 'buy' THEN 3
        ELSE NULL
    END AS behavior_type,
    DATEADD(HOUR, 8, DATEADD(SECOND, column5, '1970-01-01')) AS [datetime],
    CAST(DATEADD(HOUR, 8, DATEADD(SECOND, column5, '1970-01-01')) AS DATE) AS [date],
    DATEPART(HOUR, DATEADD(HOUR, 8, DATEADD(SECOND, column5, '1970-01-01'))) AS [hour]
FROM userBehavior
WHERE DATEADD(HOUR, 8, DATEADD(SECOND, column5, '1970-01-01')) BETWEEN '2017-11-25' AND '2017-12-04'; 

--- 2. AARRR FRAMEWORK ANALYSIS

-- A. Acquisition: Daily Active Users (DAU) and New Users
WITH UserFirstSeen AS (
    SELECT 
        uid, 
        MIN([date]) AS first_visit_date
    FROM Cleaned_UserBehavior
    GROUP BY uid
)
SELECT 
    c.[date],
    COUNT(DISTINCT c.uid) AS daily_active_users,
    COUNT(DISTINCT f.uid) AS new_acquired_users
FROM Cleaned_UserBehavior c
LEFT JOIN UserFirstSeen f ON c.uid = f.uid AND c.[date] = f.first_visit_date
GROUP BY c.[date]
ORDER BY c.[date];

-- B. Activation: Activation Rate & Bounce Analysis
WITH UserActions AS (
    SELECT 
        uid,
        MAX(CASE WHEN behavior_type = 0 THEN 1 ELSE 0 END) AS has_pv,
        MAX(CASE WHEN behavior_type IN (1, 2) THEN 1 ELSE 0 END) AS has_intent 
    FROM Cleaned_UserBehavior
    GROUP BY uid
)
SELECT 
    COUNT(uid) AS total_visitors,
    SUM(has_intent) AS activated_users,
    CAST(SUM(has_intent) * 100.0 / COUNT(uid) AS DECIMAL(10,2)) AS activation_rate_pct,
    SUM(CASE WHEN has_pv = 1 AND has_intent = 0 THEN 1 ELSE 0 END) AS bounced_users
FROM UserActions;

-- C. Retention: N-Day Cohort Analysis
WITH CohortBase AS (
    SELECT uid, MIN([date]) AS cohort_date
    FROM Cleaned_UserBehavior
    GROUP BY uid
    HAVING MIN([date]) = '2017-11-25' 
),
RetentionTracking AS (
    SELECT 
        b.cohort_date,
        DATEDIFF(DAY, b.cohort_date, u.[date]) AS day_offset,
        COUNT(DISTINCT u.uid) AS retained_users
    FROM CohortBase b
    JOIN Cleaned_UserBehavior u ON b.uid = u.uid
    GROUP BY b.cohort_date, DATEDIFF(DAY, b.cohort_date, u.[date])
)
SELECT 
    cohort_date,
    day_offset AS days_since_first_visit,
    retained_users,
    CAST(retained_users * 100.0 / MAX(retained_users) OVER(PARTITION BY cohort_date) AS DECIMAL(10,2)) AS retention_rate_pct
FROM RetentionTracking
ORDER BY days_since_first_visit;

-- D. Revenue: Conversion to Paying Users
WITH PurchaseStats AS (
    SELECT 
        COUNT(DISTINCT uid) AS total_platform_users,
        COUNT(DISTINCT CASE WHEN behavior_type = 3 THEN uid END) AS paying_users,
        SUM(CASE WHEN behavior_type = 3 THEN 1 ELSE 0 END) AS total_orders
    FROM Cleaned_UserBehavior
)
SELECT 
    total_platform_users,
    paying_users,
    CAST(paying_users * 100.0 / total_platform_users AS DECIMAL(10,2)) AS paying_user_rate_pct,
    total_orders
FROM PurchaseStats;

-- E. Referral: (Metrics excluded as external share data is not present in the current schema)

--- 3. USER CONVERSION & FUNNEL ANALYSIS

WITH FunnelStats AS (
    SELECT 
        COUNT(DISTINCT uid) AS total_uv,
        COUNT(DISTINCT CASE WHEN behavior_type = 0 THEN uid END) AS pv_users,
        COUNT(DISTINCT CASE WHEN behavior_type IN (1, 2) THEN uid END) AS interest_users,
        COUNT(DISTINCT CASE WHEN behavior_type = 3 THEN uid END) AS buyers
    FROM Cleaned_UserBehavior
)
SELECT 
    total_uv,
    CAST(interest_users * 100.0 / NULLIF(pv_users, 0) AS DECIMAL(10,2)) AS interest_conversion_pct,
    CAST(buyers * 100.0 / NULLIF(pv_users, 0) AS DECIMAL(10,2)) AS overall_buy_pct,
    (pv_users - (SELECT COUNT(DISTINCT uid) FROM Cleaned_UserBehavior WHERE behavior_type > 0)) AS bounce_users
FROM FunnelStats;

--- 4. TIME-SERIES BEHAVIOR PATTERNS
-- Daily Activity Trends
SELECT 
    [date],
    COUNT(CASE WHEN behavior_type = 0 THEN 1 END) AS daily_pv,
    COUNT(DISTINCT uid) AS daily_uv
FROM Cleaned_UserBehavior
GROUP BY [date]
ORDER BY [date];

-- Peak Hour Discovery
SELECT 
    [hour],
    COUNT(*) AS action_count
FROM Cleaned_UserBehavior
GROUP BY [hour]
ORDER BY action_count DESC; 

--- 5. USER VALUE ANALYSIS (RFM MODEL)

WITH UserMetrics AS (
    SELECT 
        uid,
        DATEDIFF(DAY, MAX([date]), '2017-12-04') AS recency,
        COUNT(*) AS frequency
    FROM Cleaned_UserBehavior
    WHERE behavior_type = 3
    GROUP BY uid
),
RFM_Scores AS (
    SELECT 
        uid,
        NTILE(4) OVER (ORDER BY recency DESC) AS r_score, 
        NTILE(4) OVER (ORDER BY frequency ASC) AS f_score  
    FROM UserMetrics
)
SELECT 
    uid,
    CASE 
        WHEN r_score >= 3 AND f_score >= 3 THEN 'High Value Champion'
        WHEN r_score <= 2 AND f_score >= 3 THEN 'At-Risk Loyal'
        ELSE 'General Customer'
    END AS user_segment
FROM RFM_Scores;
--- 6. PRODUCT PERFORMANCE ANALYSIS
-- Top 20 Categories by Sales
SELECT TOP 20 
    cat_id, 
    COUNT(*) AS total_sales
FROM Cleaned_UserBehavior
WHERE behavior_type = 3
GROUP BY cat_id
ORDER BY total_sales DESC;

-- Platform Repurchase Rate
WITH PurchaseHistory AS (
    SELECT uid, COUNT(*) AS buy_count
    FROM Cleaned_UserBehavior
    WHERE behavior_type = 3
    GROUP BY uid
)
SELECT 
    CAST(SUM(CASE WHEN buy_count >= 2 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(10,2)) AS repurchase_rate_pct
FROM PurchaseHistory;