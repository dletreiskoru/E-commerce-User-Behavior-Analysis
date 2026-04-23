USE project_database;

---ETL and Cleaning---
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

---User Conversion & Funnel Analysis---
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
    -- Bounce Rate: Users who viewed (0) but never did 1, 2, or 3
    (pv_users - (SELECT COUNT(DISTINCT uid) FROM Cleaned_UserBehavior WHERE behavior_type > 0)) AS bounce_users
FROM FunnelStats;

---Time-Series Behavior Patterns---
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

---User Value Analysis (RFM Model)---
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
        NTILE(4) OVER (ORDER BY recency DESC) AS r_score, -- Recent is better
        NTILE(4) OVER (ORDER BY frequency ASC) AS f_score  -- Frequent is better
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

---Product Performance Analysis---
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