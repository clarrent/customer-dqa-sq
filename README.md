# Customer Data Quality Audit — dirty_customers

This project is a data quality assessment built around a small mock dataset based on MySQL's Sakila database. I took the `customer` table, intentionally introduced common data errors, and renamed it `dirty_customers`;
The idea being to simulate what you'd actually encounter when a new file or data source lands on your desk before it's been validated.

The goal here isn't just to write queries. It's to show the full workflow: profile the data, find the problems, document what you found, fix what you can, and hand off the rest in a format that makes sense to whoever's reading it.

This is how I approach data quality in a real environment.

---

## What's in this repo

- `dirty_customers.csv` — the raw dataset, ready to import into MySQL Workbench
- `01_dqa_audit.sql` — all the profiling and audit queries, annotated with context for each check
- `02_cleaning_fixes.sql` — the actual fixes, with a verification SELECT before every change
- `dirty_customers_fixes.xlsx` — issue log tracking every problem found, the fix applied, and current status

---

## The dataset

599 customer records pulled from the Sakila `customer` table, with errors seeded across 12 categories. Fields: `customer_id`, `first_name`, `last_name`, `email`, `phone`, `address`, `city`, `state`, `zip`, `active`, `create_date`. All records are set in Texas.

---

## What I found

| Category | Issue | Count |
|---|---|---|
| Duplicates | Full duplicate rows | 14 |
| Duplicates | Duplicate email addresses | 40 |
| Duplicates | Duplicate phone numbers | 18 |
| Nulls | NULL email | 10 |
| Nulls | NULL first_name | 8 |
| Nulls | NULL phone | 7 |
| Blanks | Whitespace-only first_name | 5 |
| Format | Invalid zip code | 5 |
| Dates | Future create_date | 5 |
| Case | Mixed case first_name | 12 |
| Format | Invalid email format | 2 |
| Other | Inactive records | 150 |

---

## How to follow along

1. Download `dirty_customers.csv` and import it into MySQL Workbench as a table named `dirty_customers`
2. Run `01_dqa_audit.sql` section by section — each section targets a specific issue category
3. Run `02_cleaning_fixes.sql` to apply the fixes — read the comments before executing each block
4. Open `dirty_customers_fixes.xlsx` for the full issue log with before/after values and status tracking

---

## Tools

MySQL Workbench, Microsoft Excel
