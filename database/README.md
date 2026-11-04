# HR Hiring Automation System — Database

**Database:** PostgreSQL  
**Schema version:** 1.0  
**Purpose:** Initial relational schema for the HR hiring workflow and its three agents.

## Files

- `schema.sql` — creates the 17 initial database tables, indexes, constraints and `updated_at` triggers.
- `ERD.md` — Mermaid entity relationship diagram and relationship notes.

## Important design decision: Candidate vs Application

A **candidate** is a person. An **application** is that person's application for one particular job.

For example, Ali can have one row in `candidates` and two rows in `applications` if he applies for two different jobs. Each application has its own status, resume history, evaluations, screening calls and interview scheduling. This prevents the result for one job from affecting another application.

The database has a unique constraint on `(candidate_id, job_id)` to prevent duplicate applications for the same job posting. A future re-application should be handled through an explicitly designed re-application policy rather than silently creating duplicates.

## Tables

### Users and job configuration

1. `users` — HR, administrator and interviewer accounts.
2. `jobs` — job requisitions and their descriptions.
3. `job_skills` — required and preferred skills for each job.
4. `job_scoring_criteria` — configurable Agent 1 rubric and weights.
5. `job_screening_questions` — questions configured for Agent 2.

### Candidates and Agent 1

6. `candidates` — one profile per person.
7. `applications` — connects a candidate to a job and stores the recruitment status.
8. `resumes` — each uploaded resume version, extracted text and private file-storage path.
9. `resume_evaluations` — Agent 1 scores, evidence, strengths, gaps, warnings and model/rubric metadata.

### Agent 2 and Agent 3

10. `screening_calls` — each screening attempt, its consent state, transcript and summary.
11. `screening_responses` — individual questions and the candidate's answers for each call.
12. `candidate_availability` — candidate-provided interview availability windows.
13. `interviewer_availability` — interviewer availability windows from mock, manual or connected calendars.
14. `interview_schedules` — each scheduling process, assigned interviewer, HR approval and invitation information.
15. `interview_slots` — proposed and selected time slots.

### Tracking

16. `communication_logs` — email, SMS and voice-call event/delivery metadata. Transcripts remain in `screening_calls`.
17. `audit_logs` — important HR, agent and system actions and status changes.

## Where files are stored

PostgreSQL stores resume metadata, the private `storage_path`, and extracted resume text. The actual PDF/DOCX file should be kept in private file storage (for local development this can be a non-public backend storage folder; later it can be private object storage). Audio recordings, when enabled with the required consent, should also be stored privately. Do not put uploaded candidate files in the public React assets folder or commit them to GitHub.

## Create the database

Create an empty PostgreSQL database first. For example, from `psql`:

```sql
CREATE DATABASE hr_hiring_automation;
```

Then run the schema from a terminal:

```bash
psql -U postgres -d hr_hiring_automation -f database/schema.sql
```

Replace `postgres` with your PostgreSQL username if it is different. If you use pgAdmin, create the database, open its Query Tool, open `schema.sql`, and execute it.

To verify that the tables were created, connect to the database and run:

```sql
\dt
```

This schema uses `gen_random_uuid()` and enables the `pgcrypto` extension. Your PostgreSQL user must have permission to create the extension, or an administrator must enable it once.

## Key rules and constraints

- A candidate is not deleted just because HR rejects one application.
- Resume versions are retained; only one resume per application can be marked current.
- Each evaluation attempt is stored separately.
- Each screening call attempt is stored separately, and each question/answer has its own row.
- A transcript or recording cannot be stored on a call whose consent is recorded as declined or pending.
- Multiple candidate and interviewer availability windows can be stored.
- Multiple interview slots can be proposed, but only one slot per scheduling process can be marked selected.
- Only one active scheduling process per application is allowed at a time; cancelled/completed schedules remain as history.
- Status values are constrained in PostgreSQL. The FastAPI service must additionally validate allowed transitions and write audit events in the same transaction as status changes.
- Active scoring rubric weights must total 100. This cross-row rule is validated in the backend before Agent 1 runs.
- HR approval gates must be enforced in backend services, not merely hidden or disabled in the React UI.

## Before production use

This is the initial application schema, not a complete production security/compliance implementation. Before storing real candidate data, add and test authentication/authorization, secure file storage, encryption and secret management, retention/deletion procedures, backup/restore, audit access controls, and applicable privacy/consent requirements. Use synthetic data during development.

## Design updates

If the schema changes after the application starts, use versioned database migrations (for example Alembic with SQLAlchemy) instead of repeatedly running the full `schema.sql` against an existing database.
