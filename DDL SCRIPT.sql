CREATE SCHEMA IF NOT EXISTS safari_connect;
SET search_path TO safari_connect;

-- Staging table: ALL columns TEXT - accepts dirty data without failing
CREATE TABLE IF NOT EXISTS bookings_staging (
    booking_id       TEXT,
    passenger_name    TEXT, 
    passenger_phone  TEXT,
    passenger_gender TEXT, 
    passenger_city    TEXT, 
    route_code       TEXT,
    route_from       TEXT, 
    route_to          TEXT, 
    vehicle_plate    TEXT,
    vehicle_type     TEXT, 
    driver_name       TEXT, 
    driver_rating    TEXT,
    departure_date   TEXT, 
    departure_time    TEXT, 
    seat_class       TEXT,
    seats_booked     TEXT, 
    fare_per_seat     TEXT, 
    total_fare       TEXT,
    payment_method   TEXT, 
    booking_status    TEXT, 
    trip_rating      TEXT
);

select * from safari_connect.bookings_staging bs;



-- Verify import
SELECT COUNT(*) FROM bookings_staging;  -- should be ~290
SELECT * FROM bookings_staging LIMIT 10;


-- 1. Name casing problems
SELECT DISTINCT passenger_name 
FROM bookings_staging ORDER BY passenger_name LIMIT 30;

/* Problems:
 * Same name but one is in proper another is in caps also another is small 
 * There are spaces before the name, so we will use trim() to remove the spaces
 */

-- 2. Gender variants - should be only Male/Female
SELECT DISTINCT passenger_gender, COUNT(*) 
FROM bookings_staging GROUP BY passenger_gender;


-- 3. seat_class variants
SELECT DISTINCT seat_class, COUNT(*) 
FROM bookings_staging GROUP BY seat_class;

-- 4. payment_method variants
SELECT DISTINCT payment_method FROM bookings_staging;

-- 5. booking_status variants
SELECT DISTINCT booking_status FROM bookings_staging;

-- 6. Date format problems
SELECT booking_id, departure_date FROM bookings_staging
WHERE departure_date NOT SIMILAR TO '[0-9]{4}-[0-9]{2}-[0-9]{2}';


-- 7. Phone format problems
SELECT booking_id, passenger_phone FROM bookings_staging
WHERE passenger_phone LIKE '+254%' OR passenger_phone LIKE '%-%';

-- 8. Fares stored as text
SELECT booking_id, total_fare, fare_per_seat FROM bookings_staging
WHERE total_fare LIKE 'KES%' OR fare_per_seat LIKE 'KES%';

-- 9. Invalid trip ratings
SELECT booking_id, trip_rating FROM bookings_staging
WHERE trip_rating NOT IN ('1','2','3','4','5','');


-- 10. Duplicate booking_ids
SELECT booking_id, COUNT(*) FROM bookings_staging
GROUP BY booking_id HAVING COUNT(*) > 1;

-- 11. Negative seats_booked
SELECT booking_id, seats_booked FROM bookings_staging
WHERE NULLIF(REGEXP_REPLACE(seats_booked,'[^0-9-]','','g'),'')::INTEGER < 1;

--===============================================================================
--=====================actual cleaning===========================================


-------------------Clean 1 - passenger_name casing + whitespace
SELECT booking_id, passenger_name FROM bookings_staging
WHERE passenger_name != INITCAP(TRIM(passenger_name));

UPDATE bookings_staging
SET passenger_name = INITCAP(TRIM(passenger_name))
WHERE passenger_name != INITCAP(TRIM(passenger_name));

--======================Clean 2 - passenger_phone (dashes, +254, empty)
-- Remove dashes
UPDATE bookings_staging
SET passenger_phone = REGEXP_REPLACE(passenger_phone,'[^0-9]','','g')
WHERE passenger_phone LIKE '%-%';

-- Fix +254 prefix
UPDATE bookings_staging
SET passenger_phone = '0' || SUBSTRING(REGEXP_REPLACE(passenger_phone,'[^0-9]','','g'),4)
WHERE passenger_phone LIKE '+254%';

-- Set empty to NULL
UPDATE bookings_staging SET passenger_phone = NULL
WHERE TRIM(passenger_phone) = '';


--=====Clean 3 - passenger_gender (7 variants → Male / Female)
UPDATE bookings_staging
SET passenger_gender = CASE
    WHEN UPPER(TRIM(passenger_gender)) IN ('MALE','M') THEN 'Male'
    WHEN UPPER(TRIM(passenger_gender)) IN ('FEMALE','F') THEN 'Female'
    ELSE passenger_gender
END;



--Clean 4 - passenger_city (casing + empty)
UPDATE bookings_staging
SET passenger_city = INITCAP(TRIM(passenger_city))
WHERE passenger_city != INITCAP(TRIM(passenger_city));

UPDATE bookings_staging SET passenger_city = 'Unknown'
WHERE TRIM(passenger_city) = '' OR passenger_city IS NULL;



--Clean 5 - departure_date (3 formats)
-- Fix DD/MM/YYYY
UPDATE bookings_staging
SET departure_date = TO_DATE(departure_date,'DD/MM/YYYY')::TEXT
WHERE departure_date LIKE '%/%';

-- Fix DD-MM-YY (length = 8)
UPDATE bookings_staging
SET departure_date = TO_DATE(departure_date,'DD-MM-YY')::TEXT
WHERE departure_date LIKE '%-%' AND LENGTH(departure_date) = 8;

-- Fix MM-DD-YYYY (length=10, day part > 12 confirms it's MM-DD not DD-MM)
UPDATE bookings_staging
SET departure_date = TO_DATE(departure_date,'MM-DD-YYYY')::TEXT
WHERE departure_date LIKE '%-%'
  AND LENGTH(departure_date) = 10
  AND SPLIT_PART(departure_date,'-',2)::INTEGER > 12;


--Clean 6 - seat_class (abbreviations + casing)
UPDATE bookings_staging
SET seat_class = CASE
    WHEN UPPER(TRIM(seat_class)) IN ('ECONOMY','ECO','ECONOMY CLASS') THEN 'Economy'
    WHEN UPPER(TRIM(seat_class)) IN ('BUSINESS','BUS','BUSINESS CLASS') THEN 'Business'
    ELSE seat_class
END;

--Clean 7 - payment_method and booking_status
UPDATE bookings_staging
SET payment_method = CASE
    WHEN UPPER(TRIM(payment_method)) IN ('MPESA','M-PESA','M PESA') THEN 'M-Pesa'
    WHEN UPPER(TRIM(payment_method)) = 'CASH'THEN 'Cash'
    WHEN UPPER(TRIM(payment_method)) = 'CARD'THEN 'Card'
    ELSE payment_method
END;

UPDATE bookings_staging
SET booking_status = CASE
    WHEN UPPER(TRIM(booking_status)) = 'COMPLETED'  THEN 'Completed'
    WHEN UPPER(TRIM(booking_status)) = 'CANCELLED'  THEN 'Cancelled'
    WHEN UPPER(TRIM(booking_status)) = 'NO SHOW'    THEN 'No Show'
    ELSE booking_status
END;

select distinct  booking_status from safari_connect.bookings_staging;


--Clean 8 - fare_per_seat and total_fare (strip KES)
UPDATE bookings_staging
SET total_fare = REGEXP_REPLACE(total_fare,'[^0-9.]','','g')
WHERE total_fare SIMILAR TO '%[^0-9.]%';

UPDATE bookings_staging
SET fare_per_seat = REGEXP_REPLACE(fare_per_seat,'[^0-9.]','','g')
WHERE fare_per_seat SIMILAR TO '%[^0-9.]%';


select distinct fare_per_seat from safari_connect.bookings_staging;

--Clean 9 - driver_name casing
UPDATE bookings_staging
SET driver_name = INITCAP(TRIM(driver_name))
WHERE driver_name != INITCAP(TRIM(driver_name));

--Clean 10 - vehicle_type casing
UPDATE bookings_staging
SET vehicle_type = INITCAP(TRIM(vehicle_type))
WHERE vehicle_type != INITCAP(TRIM(vehicle_type));

--Clean 11 - trip_rating (invalid values → NULL)
UPDATE bookings_staging
SET trip_rating = NULL
WHERE TRIM(trip_rating) NOT IN ('1','2','3','4','5','');

-- Clean 12 - Remove negative seats and duplicates
-- Delete rows with negative seats
DELETE FROM bookings_staging
WHERE NULLIF(REGEXP_REPLACE(seats_booked,'[^0-9-]','','g'),'')::INTEGER < 1;

-- Remove exact duplicates (keep first ctid)
DELETE FROM bookings_staging
WHERE ctid NOT IN 
    (SELECT MIN(ctid) FROM bookings_staging GROUP BY booking_id);


--================================================================================
--====Step 5 - Create Production Table & Load Clean Data

CREATE TABLE IF NOT EXISTS bookings (
    booking_id        VARCHAR(10) PRIMARY KEY,
    passenger_name    VARCHAR(100),  passenger_phone  VARCHAR(15),
    passenger_gender  VARCHAR(10),   passenger_city   VARCHAR(60),
    route_code        VARCHAR(10),   route_from       VARCHAR(60),
    route_to          VARCHAR(60),   vehicle_plate    VARCHAR(15),
    vehicle_type      VARCHAR(20),   driver_name      VARCHAR(100),
    driver_rating     NUMERIC(3,1),  departure_date   DATE,
    departure_time    VARCHAR(10),   seat_class       VARCHAR(20),
    seats_booked      INTEGER,       fare_per_seat    NUMERIC(10,2),
    total_fare        NUMERIC(12,2), payment_method   VARCHAR(20),
    booking_status    VARCHAR(20),   trip_rating      INTEGER
);

INSERT INTO bookings
SELECT
    booking_id, TRIM(passenger_name),
    NULLIF(TRIM(passenger_phone),''),
    passenger_gender, COALESCE(NULLIF(TRIM(passenger_city),''),'Unknown'),
    route_code, route_from, route_to, vehicle_plate, INITCAP(TRIM(vehicle_type)),
    TRIM(driver_name),
    NULLIF(REGEXP_REPLACE(driver_rating,'[^0-9.]','','g'),'')::NUMERIC,
    departure_date::DATE,  departure_time, seat_class,
    NULLIF(REGEXP_REPLACE(seats_booked,'[^0-9]','','g'),'')::INTEGER,
    NULLIF(REGEXP_REPLACE(fare_per_seat,'[^0-9.]','','g'),'')::NUMERIC,
    NULLIF(REGEXP_REPLACE(total_fare,'[^0-9.]','','g'),'')::NUMERIC,
    payment_method, booking_status,
    NULLIF(trip_rating,'')::INTEGER
FROM bookings_staging
WHERE departure_date SIMILAR TO '[0-9]{4}-[0-9]{2}-[0-9]{2}'
  AND NULLIF(REGEXP_REPLACE(seats_booked,'[^0-9]','','g'),'')::INTEGER > 0;

-- Verify
SELECT COUNT(*) FROM bookings;  -- expect ~280+
SELECT DISTINCT booking_status FROM bookings; -- exactly: Completed, Cancelled, No Show
SELECT DISTINCT seat_class FROM bookings;     -- exactly: Economy, Business


--Step 6 - Create v_clean_trips View

CREATE OR REPLACE VIEW v_clean_trips AS
SELECT *,
    TO_CHAR(departure_date, 'YYYY-MM')    AS travel_month,
    TO_CHAR(departure_date, 'Month YYYY') AS month_label,
    TO_CHAR(departure_date, 'Day')        AS day_name,
    EXTRACT(MONTH FROM departure_date)    AS month_num,
    EXTRACT(DOW FROM departure_date)      AS day_of_week,
    (fare_per_seat * seats_booked)           AS calculated_fare,
    CASE
        WHEN trip_rating BETWEEN 4 AND 5 THEN 'Satisfied'
        WHEN trip_rating = 3 THEN 'Neutral'
        WHEN trip_rating BETWEEN 1 AND 2 THEN 'Unsatisfied'
        ELSE 'No Rating'
    END AS satisfaction
FROM bookings
WHERE booking_status = 'Completed';

-- Test
SELECT * FROM v_clean_trips LIMIT 10;
















--=========================================================
--============Cleaning=====================================


