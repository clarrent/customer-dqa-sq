-- ============================================================
-- DATA CLEANING FIXES — dirty_customers
-- ============================================================
-- Purpose:
--   This script applies targeted fixes to the issues identified
--   in 01_dqa_audit.sql. Each fix is preceded by a verification
--   SELECT so you can confirm the affected records before any
--   changes are committed.
--
--   All fixes are wrapped in transactions where appropriate.
--   Run the SELECT first, review the output, then execute the
--   UPDATE or DELETE. Do not run this script blindly end-to-end
--   without reviewing each section.
--
-- Order of operations:
--   1. Remove full duplicate rows
--   2. Fix case inconsistencies
--   3. Fix whitespace / blank issues
--   4. Null flag — flag records, do not delete
--   5. Fix invalid zip codes (where correctable)
--   6. Fix invalid email format (flag only — no guessing)
--   7. Correct future create_date records
--   8. Flag inactive records
-- ============================================================


-- ============================================================
-- FIX 1: FULL DUPLICATE ROWS
-- 14 records were confirmed as full duplicates in the audit.
-- These are cases where the same customer was entered more than
-- once with matching name, email, phone, and address.
--
-- Strategy: Keep the record with the lowest customer_id
-- (assumed to be the original entry) and delete the rest.
-- ============================================================

-- Before: confirm which records will be removed
SELECT *
FROM dirty_customers
WHERE customer_id NOT IN (
    SELECT MIN(customer_id)
    FROM dirty_customers
    GROUP BY first_name, last_name, email, phone, address
)
AND (first_name, last_name, email, phone, address) IN (
    SELECT first_name, last_name, email, phone, address
    FROM dirty_customers
    GROUP BY first_name, last_name, email, phone, address
    HAVING COUNT(*) > 1
);

-- Fix: delete confirmed duplicate rows, keep lowest customer_id
DELETE FROM dirty_customers
WHERE customer_id NOT IN (
    SELECT customer_id FROM (
        SELECT MIN(customer_id) AS customer_id
        FROM dirty_customers
        GROUP BY first_name, last_name, email, phone, address
    ) AS keep_ids
);
-- Expected: 14 rows deleted


-- ============================================================
-- FIX 2: MIXED CASE — first_name
-- 12 records have first_name stored in mixed case (e.g., 'Deborah',
-- 'David'). The standard in this dataset is UPPER case.
-- Fixing this ensures consistent string comparisons, lookups,
-- and display in downstream reports.
-- ============================================================

-- Before: confirm which records will be updated
SELECT customer_id, first_name, UPPER(first_name) AS corrected
FROM dirty_customers
WHERE BINARY first_name <> UPPER(first_name)
  AND first_name IS NOT NULL
  AND TRIM(first_name) != '';

-- Fix: standardize first_name to UPPER case
UPDATE dirty_customers
SET first_name = UPPER(first_name)
WHERE BINARY first_name <> UPPER(first_name)
  AND first_name IS NOT NULL
  AND TRIM(first_name) != '';
-- Expected: 12 rows updated


-- ============================================================
-- FIX 3: WHITESPACE / BLANK first_name
-- 5 records have a blank or whitespace-only first_name.
-- These passed the NULL check in the audit but are still
-- unusable — setting them to NULL makes them visible and
-- consistent with other missing name records.
-- ============================================================

-- Before: confirm which records will be updated
SELECT customer_id, first_name, last_name
FROM dirty_customers
WHERE TRIM(first_name) = '';

-- Fix: convert blank/whitespace first_name to NULL
UPDATE dirty_customers
SET first_name = NULL
WHERE TRIM(first_name) = '';
-- Expected: 5 rows updated


-- ============================================================
-- FIX 4: NULL first_name — FLAG FOR REVIEW
-- After fixing blanks above, there are now 13 records total
-- with a NULL first_name (8 original nulls + 5 converted blanks).
--
-- Strategy: Do not delete these records. In a real environment,
-- I would flag them for the data owner or source system to
-- provide the correct values. Deleting without confirmation
-- risks losing valid customer data.
-- ============================================================

-- Review: full list of records needing first_name resolution
SELECT customer_id, first_name, last_name, email
FROM dirty_customers
WHERE first_name IS NULL
ORDER BY customer_id;

-- Optional: add a note column to flag these for review
-- (only if the table schema supports it or if tracking externally)
-- These are documented in the accompanying Excel issue log.


-- ============================================================
-- FIX 5: INVALID ZIP CODES
-- 5 records have zip codes that do not match the expected
-- 5-digit numeric format. These cannot be auto-corrected
-- without source data — the right action is to flag them
-- and route back to the data owner.
--
-- What we found:
--   'TX750'  — looks like a state prefix was included by mistake
--   '999999' — 6 digits, clearly invalid
--   '75-001' — contains a dash, likely a formatting error
--   '7501'   — only 4 digits, truncated
--   'ABCDE'  — non-numeric, likely a test or placeholder value
-- ============================================================

-- Review: confirm all 5 invalid zip records
SELECT customer_id, city, state, zip
FROM dirty_customers
WHERE zip NOT REGEXP '^[0-9]{5}$';

-- Fix where the correction is clear: 'TX750' likely means '75000'
-- All others require source verification before any change is made.
-- Documenting as open items in the Excel issue log.

UPDATE dirty_customers
SET zip = '75000'
WHERE zip = 'TX750';
-- Expected: 1 row updated (others left as open items)


-- ============================================================
-- FIX 6: INVALID EMAIL FORMAT
-- 2 records have emails that are clearly not valid:
--   customer_id 282: 'plaintext'
--   customer_id 481: 'notanemail'
--
-- These cannot be corrected without the actual email address.
-- Setting to NULL makes them consistent with other missing
-- email records and prevents them from being used in outreach.
-- ============================================================

-- Before: confirm the 2 records
SELECT customer_id, email
FROM dirty_customers
WHERE email IS NOT NULL
  AND email NOT LIKE '%@%.%';

-- Fix: set invalid email values to NULL
UPDATE dirty_customers
SET email = NULL
WHERE email IS NOT NULL
  AND email NOT LIKE '%@%.%';
-- Expected: 2 rows updated


-- ============================================================
-- FIX 7: FUTURE create_date
-- 5 records have a create_date in the future (2027–2029).
-- These are clearly data entry errors — a customer record
-- cannot have been created on a date that hasn't happened yet.
--
-- Strategy: Set to NULL and flag for correction by the data owner.
-- Do not guess or backfill with today's date — that introduces
-- a different kind of inaccuracy.
-- ============================================================

-- Before: confirm the 5 future-dated records
SELECT customer_id, create_date
FROM dirty_customers
WHERE create_date > CURDATE();

-- Fix: set future create_date to NULL
UPDATE dirty_customers
SET create_date = NULL
WHERE create_date > CURDATE();
-- Expected: 5 rows updated


-- ============================================================
-- FIX 8: INACTIVE RECORDS — FLAG ONLY
-- 150 records have active = 0. These are not errors — inactive
-- status is a valid system state. However, they should be
-- excluded from operational processes like email campaigns,
-- billing runs, or active customer reporting.
--
-- No update needed. This is documented as a filter rule:
-- always include WHERE active = 1 in any operational query
-- against this table unless inactive records are explicitly needed.
-- ============================================================

-- Reference query: how to filter active records only
SELECT *
FROM dirty_customers
WHERE active = 1;

-- Reference query: count of active vs inactive
SELECT active, COUNT(*) AS cnt
FROM dirty_customers
GROUP BY active;


-- ============================================================
-- POST-FIX VERIFICATION
-- Run the summary report from 01_dqa_audit.sql again after
-- applying all fixes. Counts for resolved issues should be 0
-- or reduced to match only the open items flagged above.
-- ============================================================

SELECT 'NULL first_name'             AS issue, COUNT(*) AS cnt FROM dirty_customers WHERE first_name IS NULL
UNION ALL
SELECT 'NULL email',                  COUNT(*) FROM dirty_customers WHERE email IS NULL
UNION ALL
SELECT 'NULL phone',                  COUNT(*) FROM dirty_customers WHERE phone IS NULL
UNION ALL
SELECT 'Blank first_name',            COUNT(*) FROM dirty_customers WHERE TRIM(first_name) = ''
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
SELECT 'Mixed case first_name',       COUNT(*) FROM dirty_customers WHERE BINARY first_name <> UPPER(first_name) AND first_name IS NOT NULL AND TRIM(first_name) != ''
UNION ALL
SELECT 'Future create_date',          COUNT(*) FROM dirty_customers WHERE create_date > CURDATE()
UNION ALL
SELECT 'Inactive records',            COUNT(*) FROM dirty_customers WHERE active = 0
ORDER BY cnt DESC;
