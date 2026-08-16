set search_path to safari_connect;

SELECT * FROM v_clean_trips LIMIT 10;

--================================================================================
--================Question 1: Route Analysis==========================================
--Business need: The Director wants to know which routes are the backbone 
--of the business and which underperform.

/*1A - Revenue and bookings by route
Show: route_code, route_from, route_to, total_bookings, total_seats, 
total_revenue, avg_fare, avg_trip_rating. Order by total_revenue 
descending.*/

SELECT
    route_code,
    concat(route_from , ' → ' , route_to ) AS route,
    COUNT(*) AS total_bookings,
    SUM(seats_booked) AS total_seats,
    SUM(total_fare) AS total_revenue,
    ROUND(AVG(fare_per_seat), 2) AS avg_fare,
    ROUND(AVG(trip_rating), 2) AS avg_rating
FROM v_clean_trips
GROUP BY 
	route_code, 
	route_from, 
	route_to
ORDER BY total_revenue DESC;


/* 1B - Revenue per seat by route (efficiency metric)
Which route earns the most per seat sold? Show route, total_revenue, 
total_seats, and revenue_per_seat = total_revenue / total_seats.*/

--we used nullif() to avoid division-by-zero error

select 
route_code, 
route_from || ' -> ' || route_to as route,
SUM(total_fare) as total_revenue,
SUM(seats_booked) as total_seats,
round(SUM(total_fare)/ nullif(SUM(seats_booked),0),2) as revenue_per_seat
from v_clean_trips 
group by route_code ,route_from ,route_to 
order by revenue_per_seat desc;


/*1C - Route ranking with window function
Rank all routes by total revenue using RANK(). Also show each route's 
percentage of total company revenue.*/

--N/B: we use cte's and Window function

WITH route_rev AS (
    SELECT route_code, route_from || ' → ' || route_to AS route,
           SUM(total_fare) AS revenue
    FROM v_clean_trips 
    GROUP BY 
	    route_code, 
	    route_from, 
	    route_to
)
SELECT
    route, 
    revenue,
    RANK() OVER (ORDER BY revenue DESC) AS revenue_rank,
    ROUND(revenue * 100.0 / SUM(revenue) OVER (), 1) AS pct_of_total
FROM route_rev ORDER BY revenue_rank;



/*1D - Vehicle type performance
Compare Bus vs Matatu vs Minibus - total bookings, revenue, avg rating. Which vehicle type is most profitable?*/

select
    vehicle_type,
    COUNT(*) AS total_bookings,
    SUM(total_fare) AS total_revenue,
    ROUND(AVG(trip_rating), 2) AS avg_rating
FROM v_clean_trips
group by v_clean_trips.vehicle_type 
order by total_revenue desc;



--========================================================================
--======================Question 2 - Driver Performance==================
/*Business need: HR wants to know who to promote, who needs training, and 
 * whether driver rating affects passenger satisfaction.*/

/*2A - Driver summary
Show: driver_name, total_trips, total_seats_carried, total_revenue, 
avg_trip_rating, driver_rating. Order by total_revenue descending.*/

select 
driver_name,
count(*) as total_trips,
sum(seats_booked) as total_seats_carried,
SUM(total_fare) as total_revenue,
ROUND(AVG(trip_rating), 2) AS avg_trip_rating,
ROUND(AVG(driver_rating), 2) AS avg_driver_rating
from v_clean_trips
group by driver_name 
order by total_revenue desc;

-- 2B - Driver Ranking
-- Business Question:
-- Rank drivers overall by revenue and within each vehicle type.


WITH driver_totals AS (
    SELECT
        driver_name,
        vehicle_type,
        COUNT(*) AS total_trips,
        SUM(total_fare) AS total_revenue,
        ROUND(AVG(trip_rating), 2) AS avg_passenger_rating
    FROM v_clean_trips
    GROUP BY
        driver_name,
        vehicle_type
)
SELECT
    driver_name,
    vehicle_type,
    total_trips,
    total_revenue,
    avg_passenger_rating,
    RANK() OVER (ORDER BY total_revenue DESC) AS overall_rank,
    RANK() OVER (PARTITION BY vehicle_type ORDER BY total_revenue DESC) 
    AS vehicle_rank
FROM driver_totals
ORDER BY overall_rank;

/*2C - Does driver rating predict passenger satisfaction?
Group drivers into high-rated (≥ 4.5) and standard (< 4.5). 
Compare average passenger trip_rating for each group. 
Does a higher driver rating lead to happier passengers?  NO*/

SELECT
    CASE
        WHEN driver_rating >= 4.5 THEN 'High-rated'
        ELSE 'Standard'
    END AS driver_category,
    COUNT(*) AS total_trips,
    ROUND(AVG(trip_rating), 2) AS avg_passenger_rating
FROM v_clean_trips
GROUP BY
    CASE
        WHEN driver_rating >= 4.5 THEN 'High-rated'
        ELSE 'Standard'
    END
ORDER BY avg_passenger_rating DESC;


--=======================================================================
--================Question 3 - Revenue Trends============================
--Business need: The Director wants to see if Safari Connect is growing 
--and which months to focus on for expansion.


--3A - Monthly revenue with month-over-month change (CTE + LAG)
WITH monthly AS (
    SELECT
        TO_CHAR(departure_date, 'YYYY-MM') AS month,
        COUNT(*) AS bookings,
        SUM(total_fare) AS revenue
    FROM v_clean_trips
    GROUP BY TO_CHAR(departure_date, 'YYYY-MM')
)
SELECT
    month, bookings, revenue,
    LAG(revenue) OVER (ORDER BY month)                        AS prev_month,
    revenue - LAG(revenue) OVER (ORDER BY month)        AS change,
    ROUND((revenue - LAG(revenue) OVER (ORDER BY month))
        / NULLIF(LAG(revenue) OVER (ORDER BY month),0) * 100, 1)  AS change_pct
FROM monthly ORDER BY month;



/*3B - Running total of revenue
Show each month with its revenue and a cumulative running total from 
January onwards.*/

WITH monthly AS (
    SELECT
        TO_CHAR(departure_date, 'YYYY-MM') AS month,
        SUM(total_fare) AS revenue
    FROM v_clean_trips
    GROUP BY TO_CHAR(departure_date, 'YYYY-MM')
)
SELECT
    month,
    revenue,
    SUM(revenue) OVER (
        ORDER BY month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total
FROM monthly
ORDER BY month;


-- 3C - Best and Worst Three Months
-- Business Question:
-- Which months generated the highest and lowest revenue?

WITH monthly_revenue AS (
    SELECT
        TO_CHAR(departure_date, 'YYYY-MM') AS month,
        SUM(total_fare) AS total_revenue
    FROM v_clean_trips
    GROUP BY TO_CHAR(departure_date, 'YYYY-MM')
),
ranked_months AS (
    SELECT
        month,
        total_revenue,
        RANK() OVER (ORDER BY total_revenue DESC) AS highest_rank,
        RANK() OVER (ORDER BY total_revenue ASC) AS lowest_rank
    FROM monthly_revenue
)
SELECT
    month,
    total_revenue,
    highest_rank,
    lowest_rank
FROM ranked_months
WHERE highest_rank <= 3
   OR lowest_rank <= 3
ORDER BY total_revenue DESC;



--3D - Revenue by route per month (pivot)
/*Show one row per month with separate columns for the top 3 routes 
  (RT001, RT002, RT003) using CASE WHEN + SUM.*/
SELECT
    TO_CHAR(departure_date, 'YYYY-MM') AS month,
    SUM(
        CASE
            WHEN route_code = 'RT001'
            THEN total_fare
            ELSE 0
        END
    ) AS rt001_revenue,
    SUM(
        CASE
            WHEN route_code = 'RT002'
            THEN total_fare
            ELSE 0
        END
    ) AS rt002_revenue,
    SUM(
        CASE
            WHEN route_code = 'RT003'
            THEN total_fare
            ELSE 0
        END
    ) AS rt003_revenue
FROM v_clean_trips
GROUP BY TO_CHAR(departure_date, 'YYYY-MM')
ORDER BY month;



-- =============================================================================
--=================Question 4 - Passenger Insights==============================
--Business need: Marketing wants to know who Safari Connect's typical 
--traveller is.

-- 4A - Top Passenger Cities
-- Business Question:
-- Which passenger cities generate the most bookings,
-- passengers and revenue?

SELECT
    passenger_city,
    COUNT(*) AS total_bookings,
    SUM(seats_booked) AS total_seats,
    SUM(total_fare) AS total_revenue,
    ROUND(AVG(fare_per_seat), 2) AS avg_fare
FROM v_clean_trips
GROUP BY passenger_city
HAVING COUNT(*) >= 3
ORDER BY total_bookings DESC;

--4B - Gender split and seat class preference
/*Show bookings and revenue broken down by passenger_gender and seat_class. 
 Use a CASE WHEN pivot to show Economy and Business as separate columns.*/


SELECT
    passenger_gender,
    SUM(CASE
            WHEN seat_class = 'Economy' THEN 1
            ELSE 0
        END) AS economy_bookings,
    SUM(CASE
            WHEN seat_class = 'Business' THEN 1
            ELSE 0
        END) AS business_bookings,
    SUM(CASE
            WHEN seat_class = 'Economy' THEN total_fare
            ELSE 0
        END) AS economy_revenue,
    SUM(CASE
            WHEN seat_class = 'Business' THEN total_fare
            ELSE 0
        END) AS business_revenue
FROM v_clean_trips
GROUP BY passenger_gender
ORDER BY passenger_gender;


/*4C - Satisfaction breakdown (CTE)
Using a CTE, count how many trips fall into each satisfaction category 
(Satisfied / Neutral / Unsatisfied / No Rating). 
Show count and percentage of total completed trips.*/
WITH sat_counts AS (
    SELECT satisfaction, COUNT(*) AS cnt
    FROM v_clean_trips
    GROUP BY satisfaction
)
SELECT
    satisfaction,
    cnt,
    ROUND(cnt * 100.0 / SUM(cnt) OVER (), 1) AS pct
FROM sat_counts ORDER BY cnt DESC;

/*4D - Passenger quartiles by spend (NTILE)
Using a CTE for total spend per passenger, divide passengers into 4 quartiles 
using NTILE(4). Show: passenger_name, total_spent, quartile. Label quartile 4 
as 'Top Spender'.*/

WITH passenger_spend AS (
    SELECT
        passenger_name,
        SUM(total_fare) AS total_spent
    FROM v_clean_trips
    GROUP BY passenger_name
),
passenger_quartiles AS (
    SELECT
        passenger_name,
        total_spent,
        NTILE(4) OVER (ORDER BY total_spent) AS quartile
    FROM passenger_spend
)
SELECT
    passenger_name,
    total_spent,
    quartile,
    CASE
        WHEN quartile = 4 THEN 'Top Spender'
        ELSE 'Standard'
    END AS spending_category
FROM passenger_quartiles
ORDER BY total_spent DESC;



--=========================================================================
--===========Question 5 - Cancellations & Lost Revenue====================

--5A - Overall status breakdown

SELECT
    booking_status 
    ,
    COUNT(*) AS total_bookings
FROM bookings b 
GROUP BY booking_status 
ORDER BY total_bookings DESC;


--5B - Cancellation rate by route
/*Show: route_code, route, total_bookings, completed, cancelled, no_show,
 * cancellation_rate_pct.*/
SELECT
    route_code,
    route_from || ' → ' || route_to                           AS route,
    COUNT(*)                                                              AS total,
    SUM(CASE WHEN booking_status = 'Completed' THEN 1 ELSE 0 END) AS completed,
    SUM(CASE WHEN booking_status = 'Cancelled' THEN 1 ELSE 0 END) AS cancelled,
    SUM(CASE WHEN booking_status = 'No Show'  THEN 1 ELSE 0 END) AS no_show,
    ROUND(SUM(CASE WHEN booking_status IN ('Cancelled','No Show')
             THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS cancel_rate_pct
FROM bookings
GROUP BY route_code, route_from, route_to
ORDER BY cancel_rate_pct DESC;

--5C - Revenue lost from cancellations and no-shows


SELECT
    booking_status,
    COUNT(*) AS total_bookings,
    SUM(total_fare) AS lost_revenue,
    ROUND(AVG(total_fare), 2) AS average_booking_value
FROM bookings
WHERE booking_status IN ('Cancelled', 'No Show')
GROUP BY booking_status
ORDER BY lost_revenue DESC;



--=======================================================================
--===============Question 6 - Operational Patterns=======================

--Business need: Operations wants to schedule more vehicles during peak 
--times and fewer during quiet times.

--6A - Revenue by day of week

SELECT
    EXTRACT(DOW FROM departure_date)          AS day_num,
    TO_CHAR(departure_date, 'Day')            AS day_name,
    COUNT(*)                                  AS total_bookings,
    SUM(total_fare)                         AS total_revenue,
    ROUND(AVG(total_fare), 2)          AS avg_booking_value
FROM v_clean_trips
GROUP BY EXTRACT(DOW FROM departure_date), TO_CHAR(departure_date, 'Day')
ORDER BY day_num;



/*6B - Busiest departure times
Group by departure_time. Show which time slots carry the most passengers 
and generate the most revenue.*/

SELECT
    departure_time,
    COUNT(*) AS total_bookings,
    SUM(seats_booked) AS total_passengers,
    SUM(total_fare) AS total_revenue,
    ROUND(AVG(total_fare), 2) AS average_booking_value
FROM v_clean_trips
GROUP BY departure_time
ORDER BY total_passengers DESC;




/*6C - Seat utilisation by vehicle type
Compare how full each vehicle type typically runs. Show: vehicle_type, 
avg_seats_booked, and a label - 'High Load' if avg > 3, 'Medium Load' 
if 2-3, 'Low Load' if below 2.*/


SELECT
    vehicle_type,
    ROUND(AVG(seats_booked), 2) AS average_seats_booked,
    CASE
        WHEN AVG(seats_booked) > 3 THEN 'High Load'
        WHEN AVG(seats_booked) BETWEEN 2 AND 3 THEN 'Medium Load'
        ELSE 'Low Load'
    END AS load_category
FROM v_clean_trips
GROUP BY vehicle_type
ORDER BY average_seats_booked DESC;

--===============================================================================
--===============================================================================

--Create Your Views - Hand Off to BI Developer

-- View 1: Route performance
CREATE OR REPLACE VIEW v_route_performance AS
-- paste your 1A query here
SELECT
    route_code,
    concat(route_from , ' → ' , route_to ) AS route,
    COUNT(*) AS total_bookings,
    SUM(seats_booked) AS total_seats,
    SUM(total_fare) AS total_revenue,
    ROUND(AVG(fare_per_seat), 2) AS avg_fare,
    ROUND(AVG(trip_rating), 2) AS avg_rating
FROM v_clean_trips
GROUP BY 
	route_code, 
	route_from, 
	route_to
ORDER BY total_revenue DESC;

-- View 2: Driver performance
CREATE OR REPLACE VIEW v_driver_performance AS
-- paste your 2A query here
select 
driver_name,
count(*) as total_trips,
sum(seats_booked) as total_seats_carried,
SUM(total_fare) as total_revenue,
ROUND(AVG(trip_rating), 2) AS avg_trip_rating,
ROUND(AVG(driver_rating), 2) AS avg_driver_rating
from v_clean_trips
group by driver_name 
order by total_revenue desc;



-- View 3: Monthly revenue trend
CREATE OR REPLACE VIEW v_monthly_revenue AS
-- paste your 3A query (the CTE) here
WITH monthly AS (
    SELECT
        TO_CHAR(departure_date, 'YYYY-MM') AS month,
        COUNT(*) AS bookings,
        SUM(total_fare) AS revenue
    FROM v_clean_trips
    GROUP BY TO_CHAR(departure_date, 'YYYY-MM')
)
SELECT
    month, bookings, revenue,
    LAG(revenue) OVER (ORDER BY month)                        AS prev_month,
    revenue - LAG(revenue) OVER (ORDER BY month)        AS change,
    ROUND((revenue - LAG(revenue) OVER (ORDER BY month))
        / NULLIF(LAG(revenue) OVER (ORDER BY month),0) * 100, 1)  AS change_pct
FROM monthly ORDER BY month;



-- View 4: Cancellation analysis
CREATE OR REPLACE VIEW v_cancellation_analysis AS
-- paste your 5B query here
SELECT
    route_code,
    route_from || ' → ' || route_to                           AS route,
    COUNT(*)                                                              AS total,
    SUM(CASE WHEN booking_status = 'Completed' THEN 1 ELSE 0 END) AS completed,
    SUM(CASE WHEN booking_status = 'Cancelled' THEN 1 ELSE 0 END) AS cancelled,
    SUM(CASE WHEN booking_status = 'No Show'  THEN 1 ELSE 0 END) AS no_show,
    ROUND(SUM(CASE WHEN booking_status IN ('Cancelled','No Show')
             THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS cancel_rate_pct
FROM bookings
GROUP BY route_code, route_from, route_to
ORDER BY cancel_rate_pct DESC;



-- View 5: Passenger city insights
CREATE OR REPLACE VIEW v_passenger_insights AS
-- paste your 4A query here
SELECT
    passenger_city,
    COUNT(*) AS total_bookings,
    SUM(seats_booked) AS total_seats,
    SUM(total_fare) AS total_revenue,
    ROUND(AVG(fare_per_seat), 2) AS avg_fare
FROM v_clean_trips
GROUP BY passenger_city
HAVING COUNT(*) >= 3
ORDER BY total_bookings DESC;


Add Indexes

CREATE INDEX idx_bookings_depdate     ON bookings (departure_date);
CREATE INDEX idx_bookings_route       ON bookings (route_code);
CREATE INDEX idx_bookings_driver      ON bookings (driver_name);
CREATE INDEX idx_bookings_status      ON bookings (booking_status);
CREATE INDEX idx_bookings_payment     ON bookings (payment_method);
CREATE INDEX idx_bookings_vehicle     ON bookings (vehicle_type);
CREATE INDEX idx_bookings_passcity    ON bookings (passenger_city);

SELECT tablename, indexname FROM pg_indexes
WHERE schemaname = 'safari_connect';




