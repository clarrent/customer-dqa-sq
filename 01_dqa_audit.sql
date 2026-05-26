-- ============================================================
-- DATA QUALITY AUDIT (DQA) — dirty_customers
-- Analyst:  Clarrent Nguyen
-- Date:     2025
-- Tool:     MySQL Workbench 8.0+
--
-- Purpose:
--   This script profiles and audits the dirty_customers table
--   to identify data quality issues before any cleaning is applied.
--   The approach mirrors what I would do in a real onboarding or
--   intake scenario — understand the data first, then act on it.
--
-- Table:    dirty_customers
-- Source:   MySQL Sakila sample DB (customer table), intentionally
--           corrupted for DQA demonstration purposes
--
-- Columns:
--   customer_id, first_name, last_name, email, phone,
--   address, city, state, zip, active, create_date
--
-- How to use:
--   Run each section independently in MySQL Workbench.
--   Section 9 contains the full summary report — run that
--   last to validate all counts in one pass.
-- ============================================================


-- ============================================================
-- SECTION 0: RAW SAMPLE
-- Before touching anything, I always pull a raw sample first.
-- This gives me a feel for the data — formatting patterns,
-- obvious issues, and what fields look like in practice.
-- ============================================================

SELECT *
FROM dirty_customers
LIMIT 25;


-- ============================================================
-- SECTION 1: NULL ANALYSIS
-- Null values in required fields like first_name, email, and
-- phone mean those records are incomplete for operational use.
-- In a real system, nulls in these fields would cause failures
-- in email campaigns, outreach workflows, or billing processes.
-- Goal: quantify how many records are affected per field.
-- ============================================================

-- 1A. Count of records missing first_name
SELECT COUNT(*) AS cnt_null_first_name
FROM dirty_customers
WHERE first_name IS NULL;
-- Result: 8 records

-- 1B. Count of records missing last_name
SELECT COUNT(*) AS cnt_null_last_name
FROM dirty_customers
WHERE last_name IS NULL;
-- Result: 0 records

-- 1C. Count of records missing email
SELECT COUNT(*) AS cnt_null_email
FROM dirty_customers
WHERE email IS NULL;
-- Result: 10 records

-- 1D. Count of records missing phone
SELECT COUNT(*) AS cnt_null_phone
FROM dirty_customers
WHERE phone IS NULL;
-- Result: 7 records

-- 1E. Count of records missing address
SELECT COUNT(*) AS cnt_null_address
FROM dirty_customers
WHERE address IS NULL;
-- Result: 0 records

-- 1F. Row-level view — which customers are missing first_name?
--     Useful for flagging specific records for manual review or outreach.
SELECT customer_id, first_name, last_name, email
FROM dirty_customers
WHERE first_name IS NULL;

-- 1G. Row-level view — which customers are missing phone?
SELECT customer_id, first_name, last_name, phone
FROM dirty_customers
WHERE phone IS NULL;


-- ============================================================
-- SECTION 2: BLANK / WHITESPACE ANALYSIS
-- Blank strings and whitespace-only values are not the same
-- as nulls — they pass null checks but are still unusable.
-- These are easy to miss and often slip through validation.
-- ============================================================

-- 2A. Blank or whitespace-only first_name
SELECT customer_id, first_name, last_name
FROM dirty_customers
WHERE TRIM(first_name) = '';
-- Result: 5 records

-- 2B. Blank or whitespace-only last_name
SELECT customer_id, first_name, last_name
FROM dirty_customers
WHERE TRIM(last_name) = '';

-- 2C. Blank or whitespace-only email
SELECT customer_id, email
FROM dirty_customers
WHERE TRIM(email) = '';

-- 2D. Leading or trailing spaces in first_name
--     These look clean on the surface but cause mismatches
--     in joins, lookups, and downstream reporting.
SELECT customer_id, first_name
FROM dirty_customers
WHERE first_name <> TRIM(first_name);

-- 2E. Combined count — first_name is either NULL or has whitespace issues
SELECT COUNT(*) AS cnt_first_name_null_or_whitespace
FROM dirty_customers
WHERE first_name IS NULL
   OR first_name <> TRIM(first_name);


-- ============================================================
-- SECTION 3: DUPLICATE ANALYSIS
-- Duplicates create inflated counts, double-billing risk,
-- and corrupted customer profiles. I check three levels:
-- name-level, field-level (email/phone), and full row matches.
-- ============================================================

-- 3A. Duplicate first_name + last_name combinations
--     This surfaces name collisions — could be the same person
--     entered twice, or two different people with the same name.
--     Need to drill in to distinguish.
SELECT first_name, last_name, COUNT(*) AS cnt
FROM dirty_customers
GROUP BY first_name, last_name
HAVING COUNT(*) > 1
ORDER BY cnt DESC;

-- 3B. Drill-in example: confirmed exact duplicate (same customer, different ID)
--     MARY WALKER appears twice with matching contact info — true duplicate.
SELECT *
FROM dirty_customers
WHERE first_name = 'MARY'
  AND last_name = 'WALKER';

-- 3C. Drill-in example: name collision, not a duplicate
--     DOROTHY HERNANDEZ shares a name but is a different person.
SELECT *
FROM dirty_customers
WHERE first_name = 'DOROTHY'
  AND last_name = 'HERNANDEZ';

-- 3D. Duplicate email addresses
--     Same email tied to multiple customer_ids is a data integrity problem.
--     Could indicate a shared account, a bad merge, or a re-entry error.
SELECT email, COUNT(*) AS cnt
FROM dirty_customers
WHERE email IS NOT NULL
GROUP BY email
HAVING COUNT(*) > 1
ORDER BY cnt DESC;
-- Result: 40 records flagged across duplicate email groups

-- 3E. Duplicate phone numbers
--     Same logic as email — same phone on multiple records needs investigation.
SELECT phone, COUNT(*) AS cnt
FROM dirty_customers
WHERE phone IS NOT NULL
GROUP BY phone
HAVING COUNT(*) > 1
ORDER BY cnt DESC;
-- Result: 18 records flagged across duplicate phone groups

-- 3F. Full row duplicates — all key fields match exactly
--     These are the clearest cases: same person, entered more than once.
--     Safe to remove the duplicate after confirming no child record dependency.
SELECT first_name, last_name, email, phone, address, COUNT(*) AS cnt
FROM dirty_customers
GROUP BY first_name, last_name, email, phone, address
HAVING COUNT(*) > 1
ORDER BY cnt DESC;
-- Result: 14 records confirmed as full duplicates


-- ============================================================
-- SECTION 4: FORMAT VALIDATION
-- Invalid formats break integrations and downstream systems.
-- A bad email format means a marketing tool rejects the record.
-- A bad zip means a shipping or geo-lookup fails silently.
-- ============================================================

-- 4A. Invalid email format — missing @ symbol or domain
--     This catches obvious junk values like 'plaintext' or 'notanemail'.
--     Note: this is a basic check. A full regex would catch more edge cases.
SELECT customer_id, email
FROM dirty_customers
WHERE email IS NOT NULL
  AND email NOT LIKE '%@%.%';
-- Result: 2 records (customer_id 282: 'plaintext', customer_id 481: 'notanemail')

-- 4B. Invalid zip code — must be exactly 5 numeric digits
--     Anything outside that pattern (letters, dashes, 4 or 6 digits)
--     will fail postal validation and geo-enrichment lookups.
SELECT customer_id, zip
FROM dirty_customers
WHERE zip NOT REGEXP '^[0-9]{5}$';
-- Result: 5 records with malformed zips (e.g., 'TX750', '999999', '75-001', '7501', 'ABCDE')

-- 4C. Invalid phone format — expected pattern: (###) ###-####
--     All phones in this dataset use a consistent format.
--     This query flags anything that deviates from it.
SELECT customer_id, phone
FROM dirty_customers
WHERE phone IS NOT NULL
  AND phone NOT REGEXP '^\([0-9]{3}\) [0-9]{3}-[0-9]{4}$';


-- ============================================================
-- SECTION 5: CASE CONSISTENCY
-- Inconsistent casing causes mismatches in string comparisons,
-- display issues in reporting, and breaks exact-match lookups.
-- This dataset standardizes names in UPPER CASE — any deviation
-- needs to be flagged and corrected.
--
-- The BINARY keyword forces a case-sensitive comparison.
-- Without it, MySQL treats 'mary' and 'MARY' as equal.
-- ============================================================

-- 5A. first_name not stored in UPPER case
SELECT customer_id, first_name, last_name
FROM dirty_customers
WHERE BINARY first_name <> UPPER(first_name)
  AND first_name IS NOT NULL
  AND TRIM(first_name) != '';
-- Result: 12 records with mixed case first_name
-- Examples: 'Deborah', 'David', 'Carol', 'Barbara', 'Michelle'

-- 5B. last_name not stored in UPPER case
SELECT customer_id, first_name, last_name
FROM dirty_customers
WHERE BINARY last_name <> UPPER(last_name)
  AND last_name IS NOT NULL
  AND TRIM(last_name) != '';
-- Result: 0 records — last_name is consistently cased


-- ============================================================
-- SECTION 6: DATE INTEGRITY
-- Date fields are a common source of silent errors.
-- A future create_date means the record was either entered
-- incorrectly or fabricated. Out-of-range dates suggest a
-- formatting or import issue. Missing dates leave gaps in
-- any time-based analysis or reporting.
-- ============================================================

-- 6A. Future create_date — date is beyond today
--     These records were either entered with the wrong year
--     or represent test/placeholder data that snuck into production.
SELECT customer_id, create_date
FROM dirty_customers
WHERE create_date > CURDATE();
-- Result: 5 records with future dates (2027, 2028, 2029)

-- 6B. NULL or missing create_date
SELECT customer_id, create_date
FROM dirty_customers
WHERE create_date IS NULL;
-- Result: 0 records — no missing dates found

-- 6C. Out-of-range create_date — before system go-live
--     Adjust the lower bound to match when your system actually went live.
--     Anything before that date is suspect.
SELECT customer_id, create_date
FROM dirty_customers
WHERE create_date < '2000-01-01'
   OR create_date > CURDATE();


-- ============================================================
-- SECTION 7: REFERENTIAL / LOGICAL INTEGRITY
-- These checks validate that field values make sense in context
-- — not just that they exist, but that they conform to expected
-- rules for the region, format, or relationship between fields.
-- ============================================================

-- 7A. State not a valid 2-letter abbreviation
--     All records in this dataset are in Texas (TX).
--     Any state value that isn't exactly 2 uppercase letters is invalid.
SELECT customer_id, city, state, zip
FROM dirty_customers
WHERE state NOT REGEXP '^[A-Z]{2}$'
   OR state IS NULL;
-- Result: 0 — all records are TX

-- 7B. Zip not matching expected Texas prefix range
--     Texas zip codes begin with 75–79.
--     Any TX record outside that range likely has a bad zip.
SELECT customer_id, city, state, zip
FROM dirty_customers
WHERE state = 'TX'
  AND zip NOT REGEXP '^7[5-9][0-9]{3}$';
-- Result: returns records with malformed zips confirmed in Section 4B


-- ============================================================
-- SECTION 8: OTHER FLAGS
-- Catch-all for records that are technically valid but still
-- warrant a second look before going into production or reporting.
-- ============================================================

-- 8A. Inactive customer records (active = 0)
--     These records exist in the system but are not operationally active.
--     Depending on the use case, they may need to be excluded from
--     campaigns, billing runs, or customer-facing reports.
SELECT customer_id, first_name, last_name, active
FROM dirty_customers
WHERE active = 0;
-- Result: 150 inactive records

-- 8B. Invalid active flag — anything other than 0 or 1
--     The active field should be a boolean (0 or 1).
--     Any other value indicates a data entry or import error.
SELECT customer_id, active
FROM dirty_customers
WHERE active NOT IN (0, 1)
   OR active IS NULL;

-- 8C. Negative customer_id
--     IDs should never be negative. If any exist, it points to
--     a system error, a bad import, or a manual override gone wrong.
SELECT customer_id
FROM dirty_customers
WHERE customer_id < 0;
-- Result: 0 — no negative IDs found


-- ============================================================
-- SECTION 9: FULL DQA SUMMARY REPORT
-- This is the single query I would send to a manager or include
-- in a data intake report. Each row represents one issue category
-- with a count of affected records.
--
-- Sorted by count descending so the highest-volume problems
-- surface at the top — that's where I start when prioritizing fixes.
-- ============================================================

SELECT 'NULL first_name'             AS issue, COUNT(*) AS cnt FROM dirty_customers WHERE first_name IS NULL
UNION ALL
SELECT 'NULL last_name',              COUNT(*) FROM dirty_customers WHERE last_name IS NULL
UNION ALL
SELECT 'NULL email',                  COUNT(*) FROM dirty_customers WHERE email IS NULL
UNION ALL
SELECT 'NULL phone',                  COUNT(*) FROM dirty_customers WHERE phone IS NULL
UNION ALL
SELECT 'NULL address',                COUNT(*) FROM dirty_customers WHERE address IS NULL
UNION ALL
SELECT 'Blank first_name',            COUNT(*) FROM dirty_customers WHERE TRIM(first_name) = ''
UNION ALL
SELECT 'Blank last_name',             COUNT(*) FROM dirty_customers WHERE TRIM(last_name) = ''
UNION ALL
SELECT 'Blank email',                 COUNT(*) FROM dirty_customers WHERE TRIM(email) = ''
UNION ALL
SELECT 'Whitespace in first_name',    COUNT(*) FROM dirty_customers WHERE first_name IS NOT NULL AND first_name <> TRIM(first_name)
UNION ALL
SELECT 'Duplicate email',             COUNT(*) FROM dirty_customers WHERE email IN (SELECT email FROM dirty_customers WHERE email IS NOT NULL GROUP BY email HAVING COUNT(*) > 1)
UNION ALL
SELECT 'Duplicate phone',             COUNT(*) FROM dirty_customers WHERE phone IN (SELECT phone FROM dirty_customers WHERE phone IS NOT NULL GROUP BY phone HAVING COUNT(*) > 1)
UNION ALL
SELECT 'Full duplicate rows',         COUNT(*) FROM (SELECT first_name, last_name, email, phone, address, COUNT(*) FROM dirty_customers GROUP BY first_name, last_name, email, phone, address HAVING COUNT(*) > 1) sub
UNION ALL
SELECT 'Invalid email format',        COUNT(*) FROM dirty_customers WHERE email IS NOT NULL AND email NOT LIKE '%@%.%'
UNION ALL
SELECT 'Invalid zip format',          COUNT(*) FROM dirty_customers WHERE zip NOT REGEXP '^[0-9]{5}$'
UNION ALL
SELECT 'Invalid phone format',        COUNT(*) FROM dirty_customers WHERE phone IS NOT NULL AND phone NOT REGEXP '^\([0-9]{3}\) [0-9]{3}-[0-9]{4}$'
UNION ALL
SELECT 'Mixed case first_name',       COUNT(*) FROM dirty_customers WHERE BINARY first_name <> UPPER(first_name) AND first_name IS NOT NULL AND TRIM(first_name) != ''
UNION ALL
SELECT 'Mixed case last_name',        COUNT(*) FROM dirty_customers WHERE BINARY last_name <> UPPER(last_name) AND last_name IS NOT NULL AND TRIM(last_name) != ''
UNION ALL
SELECT 'Future create_date',          COUNT(*) FROM dirty_customers WHERE create_date > CURDATE()
UNION ALL
SELECT 'NULL create_date',            COUNT(*) FROM dirty_customers WHERE create_date IS NULL
UNION ALL
SELECT 'Out of range create_date',    COUNT(*) FROM dirty_customers WHERE create_date < '2000-01-01'
UNION ALL
SELECT 'Invalid state format',        COUNT(*) FROM dirty_customers WHERE state NOT REGEXP '^[A-Z]{2}$' OR state IS NULL
UNION ALL
SELECT 'Inactive records',            COUNT(*) FROM dirty_customers WHERE active = 0
UNION ALL
SELECT 'Invalid active flag',         COUNT(*) FROM dirty_customers WHERE active NOT IN (0, 1) OR active IS NULL
UNION ALL
SELECT 'Negative customer_id',        COUNT(*) FROM dirty_customers WHERE customer_id < 0
ORDER BY cnt DESC;
