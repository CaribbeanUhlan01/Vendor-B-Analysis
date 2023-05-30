-- / Created by Hans Schaper                       \
-- | 05/10/2023                                    |
-- | General Analysis of Millennium                |
-- \ inspections from 01/13 - 05/23                /


-- Since there's no built-in function to 
-- convert int to month name, let's build one

CREATE FUNCTION dbo.MonthName (@Order_month INT)
RETURNS VARCHAR(20)
AS
BEGIN
	DECLARE @MonthName VARCHAR(20);
	SELECT @MonthName = CASE @Order_month
						   WHEN 1 THEN 'January'
                           WHEN 2 THEN 'February'
                           WHEN 3 THEN 'March'
                           WHEN 4 THEN 'April'
                           WHEN 5 THEN 'May'
                           WHEN 6 THEN 'June'
                           WHEN 7 THEN 'July'
                           WHEN 8 THEN 'August'
                           WHEN 9 THEN 'September'
                           WHEN 10 THEN 'October'
                           WHEN 11 THEN 'November'
                           WHEN 12 THEN 'December'
                       END;
					return @MonthName;
END;
-- END of function 
	









-- The order weekday was imported as a float
-- rather than an integer, so let's change that:
ALTER TABLE mu_table
ALTER COLUMN order_day int



-- Let's start by looking at the number
-- of inspections per year
ALTER VIEW mu_insps_per_year AS
SELECT order_year, COUNT (*) AS sum_insps_year 
FROM mu_table 
GROUP BY order_year


-- Number of inspections per day of week
CREATE VIEW mu_insps_per_weekday AS
SELECT DATENAME(weekday, order_day) AS weekday_name, COUNT(*) AS sum_insps_day
FROM mu_table
GROUP BY order_day
ORDER BY order_day OFFSET 0 ROWS;  -- This "OFFSET" allows for an "ORDER BY" to be stored in the view


-- Number of inspections per month 
CREATE VIEW mu_insps_per_month AS
SELECT dbo.MonthName(order_month) AS month, COUNT(*) AS sum_insps_month
FROM mu_table
GROUP BY order_month
ORDER BY order_month OFFSET 0 ROWS;  -- This "OFFSET" allows for an "ORDER BY" to be stored in the view


-- Number of inspections per state
CREATE VIEW mu_insps_per_state AS
SELECT State, COUNT(*) AS sum_insps_state
FROM mu_table 
GROUP BY State
ORDER BY COUNT(*) DESC OFFSET 0 ROWS;


-- Let's look at instances of disposition codes
-- we'll have to create a function to extract the disp. code
-- from the Mueller table
ALTER VIEW mu_disp_code_distribution AS
SELECT UW_Action AS Disposition_Code, COUNT(*) AS sum_disp_code
FROM mu_table
GROUP BY UW_Action
ORDER BY COUNT(*) DESC OFFSET 0 ROWS;

-- Let's look at instances of closeout codes
-- THIS IS NOT AVAILABLE FOR MUELLER 
--SELECT Closeout_Code, COUNT(*) AS sum_inps_per_closeout_code
--FROM mi_table
--GROUP BY Closeout_Code
--ORDER BY COUNT(*) DESC;

-- Let's look at instances of order sources
-- THIS IS NOT AVAILABLE FOR MUELLER 
--SELECT Order_Source, COUNT(*) AS sum_insps_per_ordr_source
--FROM mi_table
--GROUP BY Order_Source
--ORDER BY COUNT(*) DESC;


-- Let's look at total living area per state
CREATE VIEW mu_avg_tla_per_state AS
SELECT state, CAST(AVG(Square_Footage) AS DECIMAL (16,2)) AS avg_total_living_area
FROM mu_table
GROUP BY state
ORDER BY avg_total_living_area DESC OFFSET 0 ROWS

-- Let's look at the distribution of age built
-- THIS IS NOT AVAILABLE IN MUELLER
--CREATE VIEW mi_year_built_distribution AS
--SELECT inspection_year_built, COUNT(*) AS sum_insps_per_year_built
--FROM mi_table
--GROUP BY Inspection_Year_Built
--ORDER BY COUNT(*) DESC OFFSET 0 ROWS;


-- Let's look at the final stack distribution
-- THIS IS NOT AVAILABLE IN MUELLER
--CREATE VIEW mi_stack_distribution AS
--SELECT Stack, COUNT(*) AS sum_insps_per_stack
--FROM mi_table
--GROUP BY stack
--ORDER BY COUNT(*) DESC OFFSET 0 ROWS;


-- Let's look at coverage discrepancy overall
ALTER VIEW mu_average_overall_variation AS
SELECT CAST(AVG(Prcnt_Val) / 100 AS "DECIMAL"(16,2)) AS average_variation
FROM mu_table;


-- Let's look at average variation per state
ALTER VIEW mu_var_per_state AS
SELECT State, CAST(AVG(Prcnt_Val) / 100 AS "DECIMAL"(16,2)) AS average_variation_state,
average_variation - CAST(AVG(Prcnt_Val) / 100 AS "DECIMAL"(16,2)) AS diff_from_overall_avg_val
FROM mu_table, mu_average_overall_variation
GROUP BY state, average_variation;


-- Let's look at average variation per disposition code
CREATE VIEW mu_avg_variation_per_last_disp_code AS
SELECT UW_Action, CAST(AVG(Prcnt_Val) / 100 AS "DECIMAL"(16,2)) AS average_variation_per_disp
FROM mu_table, mu_average_overall_variation
GROUP BY UW_Action, average_variation
ORDER BY average_variation_per_disp DESC OFFSET 0 ROWS;


-- Let's look at the most common disposition codes per state
CREATE VIEW mu_top_disp_codes_per_state AS
SELECT state, UW_Action, top_disp_code_per_state
FROM (
	SELECT state, UW_Action, COUNT(UW_Action) AS top_disp_code_per_state,
		   ROW_NUMBER() OVER (PARTITION BY state ORDER BY COUNT(UW_Action) DESC) AS row_num
	FROM mu_table
	GROUP BY state, UW_Action
) AS subquery
WHERE row_num <= 3
ORDER BY state OFFSET 0 ROWS;


-- Let's look at how long orders take to complete on average
-- We first haveto convert them from nvarchar to a date format
UPDATE mi_table
SET Order_Date = CONVERT(date, Order_Date)
WHERE Order_Date IS NOT NULL;

UPDATE mi_table
SET Date_Worked = CONVERT(date, Date_Worked)
WHERE Date_Worked IS NOT NULL;

UPDATE mi_table
SET Complete_Date = CONVERT(date, Complete_Date)
WHERE Complete_Date IS NOT NULL;

ALTER TABLE mi_table
ALTER COLUMN Order_Date DATE;

ALTER TABLE mi_table
ALTER COLUMN Complete_Date DATE;

ALTER TABLE mi_table
ALTER COLUMN Date_Worked DATE;


-- Calculating the average completion time in days 
CREATE VIEW mu_avg_completion_days AS 
SELECT AVG(DATEDIFF(day, Ordered, Completed)) AS completion_time_days
FROM mu_table;

-- Now that we have the overall average, let's look at how each state compares
CREATE VIEW mu_completion_times_per_state AS
SELECT State, AVG(DATEDIFF(day, Ordered, Completed)) AS completion_time_days_state,
AVG(DATEDIFF(day, Ordered, Completed)) - completion_time_days AS variance_from_national_average
FROM mu_table, mu_avg_completion_days
GROUP BY State, completion_time_days
ORDER BY completion_time_days_state OFFSET 0 ROWS;

-- Let's look at average Coverage A per state AND year
CREATE VIEW mu_coverage_changes_per_state_and_year AS
SELECT State, Order_Year, CAST(AVG(Coverage_A_In) AS INT) AS avg_coverage, 
CAST((((AVG(Coverage_A_In)) - LAG(AVG(Coverage_A_In)) OVER (PARTITION BY State ORDER BY Order_Year)) / LAG(AVG(Coverage_A_In)) OVER (PARTITION BY State ORDER BY Order_Year)) * 100 AS DECIMAL (16,2)) AS YoY_Change
FROM mu_table
GROUP BY State, Order_Year
ORDER BY State, Order_Year OFFSET 0 ROWS;


-- let's look at avergae Coverage A per state only
CREATE VIEW mu_coverage_a_per_state AS 
SELECT State, CAST(AVG(Coverage_A_In) AS INT) AS avg_coverage
FROM mu_table
GROUP BY State
ORDER BY avg_coverage DESC OFFSET 0 ROWS;


-- Let's look at average variance per state
CREATE VIEW mu_avg_variance_per_state AS 
SELECT State, CAST(AVG(Prcnt_Val) / 100 AS "DECIMAL"(16,2)) AS variance_prcnt_state
FROM mu_table
GROUP BY State
ORDER BY AVG(Prcnt_Val) DESC OFFSET 0 ROWS;

-- Let's look at average time passed between inspection being worked and being completed
ALTER VIEW mu_inspection_SLA_per_state_AND_year AS
SELECT State, order_year, AVG(DATEDIFF(DAY, Date_Assigned, Completed)) AS inspection_SLA_days
FROM mu_table
GROUP BY State, order_year
ORDER BY State, order_year OFFSET 0 ROWS;

-- Average time between inspection being worked and being completed per state
CREATE VIEW mu_inspection_SLA_per_state AS
SELECT State,  AVG(DATEDIFF(DAY, Date_Assigned, Completed)) AS inspection_SLA_days
FROM mu_table
GROUP BY State
ORDER BY inspection_SLA_days DESC OFFSET 0 ROWS;


-- Let's look at number of inspections per year
SELECT * FROM mu_insps_per_year
ORDER BY order_year;

-- Number of inspections per week day
SELECT * FROM mu_insps_per_weekday

-- Number of inspections per month 
SELECT * FROM mu_insps_per_month

-- Number of inspections per state
SELECT * FROM mu_insps_per_state

-- Distribution of disposition codes for Mueller
SELECT * FROM mu_disp_code_distribution

-- TLA per state
SELECT * FROM  mu_avg_tla_per_state

-- Average national variation  
SELECT * FROM mu_average_overall_variation

-- Average variation per state
SELECT * FROM mu_var_per_state

-- Average variation per disposition code
SELECT * FROM mu_avg_variation_per_last_disp_code

-- Most common disposition codes per state
SELECT * FROM mu_top_disp_codes_per_state

-- Average completion for mueller
SELECT * FROM mu_avg_completion_days

-- Average completion times per state
SELECT * FROM mu_completion_times_per_state

-- Coverage changes per state
SELECT * FROM mu_coverage_changes_per_state_and_year

-- Coverage A per state
SELECT * FROM mu_coverage_a_per_state

-- Average variance per state
SELECT * FROM mu_avg_variance_per_state

-- inspection SLA per state AND year
SELECT * FROM mu_inspection_SLA_per_state_AND_year

-- AVG inspection SLA per state
SELECT * FROM mu_inspection_SLA_per_state
