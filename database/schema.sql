-- ============================================================================
-- AI-Powered HR Hiring Automation System
-- PostgreSQL database schema - Version 1.0
-- Generated: 2026-11-03
--
-- Design principles:
--   1. A candidate is a person; an application is that person's application
--      for one specific job.
--   2. Scores, screening calls, availability, scheduling and status belong to
--      an application, not to the candidate's global profile.
--   3. Historical resumes, evaluations, screening attempts and audit events
--      are retained; normal workflow actions must not delete them.
--   4. AI recommendations never replace an authorized HR decision.
--
-- Run against a NEW/EMPTY database. This is an initial schema, not a migration
-- script for an existing database.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- 1. USERS
-- HR recruiters, administrators and interviewers who can access the system.
-- ---------------------------------------------------------------------------
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name       VARCHAR(200) NOT NULL,
    email           VARCHAR(255) NOT NULL,
    password_hash   TEXT NOT NULL,
    role            VARCHAR(30) NOT NULL
                    CHECK (role IN ('HR', 'ADMIN', 'INTERVIEWER')),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX uq_users_email_lower ON users (LOWER(email));

-- ---------------------------------------------------------------------------
-- 2. JOBS
-- Each row is one job/requisition created by HR.
-- ---------------------------------------------------------------------------
CREATE TABLE jobs (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title                   VARCHAR(255) NOT NULL,
    description             TEXT NOT NULL,
    min_experience_years    NUMERIC(4,1)
                            CHECK (min_experience_years IS NULL OR min_experience_years >= 0),
    location                VARCHAR(255),
    work_mode               VARCHAR(20)
                            CHECK (work_mode IS NULL OR work_mode IN ('ONSITE', 'REMOTE', 'HYBRID')),
    employment_type         VARCHAR(30)
                            CHECK (employment_type IS NULL OR employment_type IN
                                   ('FULL_TIME', 'PART_TIME', 'CONTRACT', 'INTERNSHIP', 'TEMPORARY')),
    status                  VARCHAR(20) NOT NULL DEFAULT 'DRAFT'
                            CHECK (status IN ('DRAFT', 'OPEN', 'CLOSED', 'ARCHIVED')),
    created_by              UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_created_by ON jobs(created_by);

-- ---------------------------------------------------------------------------
-- 3. JOB_SKILLS
-- Normalized list of required and preferred skills for a job.
-- ---------------------------------------------------------------------------
CREATE TABLE job_skills (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id          UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    skill_name      VARCHAR(150) NOT NULL,
    skill_type      VARCHAR(20) NOT NULL
                    CHECK (skill_type IN ('REQUIRED', 'PREFERRED')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX uq_job_skills_name_type
    ON job_skills (job_id, LOWER(skill_name), skill_type);
CREATE INDEX idx_job_skills_job_id ON job_skills(job_id);

-- ---------------------------------------------------------------------------
-- 4. JOB_SCORING_CRITERIA
-- Configurable scoring rubric. The active weights for a job should total 100.
-- The API validates the total before allowing an evaluation to run.
-- ---------------------------------------------------------------------------
CREATE TABLE job_scoring_criteria (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id          UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    criterion_name  VARCHAR(150) NOT NULL,
    description     TEXT,
    weight          NUMERIC(5,2) NOT NULL CHECK (weight >= 0 AND weight <= 100),
    sort_order      INTEGER NOT NULL DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_job_scoring_criterion UNIQUE (job_id, criterion_name)
);

CREATE INDEX idx_job_scoring_criteria_job_id ON job_scoring_criteria(job_id);

-- ---------------------------------------------------------------------------
-- 5. JOB_SCREENING_QUESTIONS
-- Questions configured for the screening agent for a particular job.
-- ---------------------------------------------------------------------------
CREATE TABLE job_screening_questions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id          UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    question_text   TEXT NOT NULL,
    question_category VARCHAR(100),
    display_order   INTEGER NOT NULL DEFAULT 1 CHECK (display_order > 0),
    is_required     BOOLEAN NOT NULL DEFAULT TRUE,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_job_question_order UNIQUE (job_id, display_order)
);

CREATE INDEX idx_job_screening_questions_job_id ON job_screening_questions(job_id);

-- ---------------------------------------------------------------------------
-- 6. CANDIDATES
-- One row per person. A candidate can have applications for many jobs.
-- Email is nullable because a resume may be unreadable or omit an email.
-- ---------------------------------------------------------------------------
CREATE TABLE candidates (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    first_name      VARCHAR(100),
    last_name       VARCHAR(100),
    email           VARCHAR(255),
    phone_number    VARCHAR(50),
    linkedin_url    TEXT,
    portfolio_url   TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX uq_candidates_email_lower
    ON candidates (LOWER(email)) WHERE email IS NOT NULL;
CREATE INDEX idx_candidates_phone_number ON candidates(phone_number);

-- ---------------------------------------------------------------------------
-- 7. APPLICATIONS
-- The central record for one candidate applying to one particular job.
-- This table owns the recruitment status, not the candidates table.
-- ---------------------------------------------------------------------------
CREATE TABLE applications (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id        UUID NOT NULL REFERENCES candidates(id) ON DELETE RESTRICT,
    job_id              UUID NOT NULL REFERENCES jobs(id) ON DELETE RESTRICT,
    status              VARCHAR(50) NOT NULL DEFAULT 'RESUME_RECEIVED'
                        CHECK (status IN (
                            'RESUME_RECEIVED',
                            'NEEDS_MANUAL_REVIEW',
                            'SCORED_HR_REVIEW',
                            'APPROVED_FOR_SCREENING',
                            'SCREENING_PENDING',
                            'SCREENING_COMPLETED_HR_REVIEW',
                            'APPROVED_FOR_INTERVIEW',
                            'INTERVIEW_PROPOSED',
                            'INTERVIEW_SCHEDULED',
                            'REJECTED',
                            'CLOSED',
                            'WITHDRAWN'
                        )),
    application_source  VARCHAR(100),
    decision_reason     TEXT,
    applied_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_candidate_job_application UNIQUE (candidate_id, job_id)
);

CREATE INDEX idx_applications_job_status ON applications(job_id, status);
CREATE INDEX idx_applications_candidate_id ON applications(candidate_id);
CREATE INDEX idx_applications_status ON applications(status);

-- ---------------------------------------------------------------------------
-- 8. RESUMES
-- One application may have multiple uploaded resume versions.
-- The actual PDF/DOCX is kept in private file storage; storage_path points to it.
-- Extracted text and processing metadata are stored in PostgreSQL.
-- ---------------------------------------------------------------------------
CREATE TABLE resumes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id      UUID NOT NULL REFERENCES applications(id) ON DELETE RESTRICT,
    original_filename   VARCHAR(255) NOT NULL,
    storage_path        TEXT NOT NULL,
    mime_type           VARCHAR(100) NOT NULL
                        CHECK (mime_type IN (
                            'application/pdf',
                            'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
                        )),
    file_size_bytes     BIGINT NOT NULL CHECK (file_size_bytes > 0),
    file_sha256         CHAR(64),
    extracted_text      TEXT,
    extraction_status   VARCHAR(30) NOT NULL DEFAULT 'PENDING'
                        CHECK (extraction_status IN ('PENDING', 'SUCCEEDED', 'FAILED', 'NEEDS_MANUAL_REVIEW')),
    extraction_error    TEXT,
    version_number      INTEGER NOT NULL DEFAULT 1 CHECK (version_number > 0),
    is_current          BOOLEAN NOT NULL DEFAULT TRUE,
    uploaded_by         UUID REFERENCES users(id) ON DELETE SET NULL,
    uploaded_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    extracted_at        TIMESTAMPTZ,
    CONSTRAINT uq_resume_version UNIQUE (application_id, version_number),
    CONSTRAINT ck_resume_sha256 CHECK (file_sha256 IS NULL OR file_sha256 ~ '^[0-9a-fA-F]{64}$')
);

-- Only one resume can be marked current for an application.
CREATE UNIQUE INDEX uq_one_current_resume_per_application
    ON resumes(application_id) WHERE is_current = TRUE;
CREATE INDEX idx_resumes_application_id ON resumes(application_id);
CREATE INDEX idx_resumes_extraction_status ON resumes(extraction_status);

-- ---------------------------------------------------------------------------
-- 9. RESUME_EVALUATIONS
-- Stores each Agent 1 evaluation attempt. Multiple attempts are preserved.
-- JSONB fields store structured scores, evidence, strengths and warnings.
-- ---------------------------------------------------------------------------
CREATE TABLE resume_evaluations (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resume_id                   UUID NOT NULL REFERENCES resumes(id) ON DELETE RESTRICT,
    overall_score               NUMERIC(5,2) NOT NULL CHECK (overall_score >= 0 AND overall_score <= 100),
    criterion_scores            JSONB NOT NULL DEFAULT '{}'::JSONB
                                CHECK (jsonb_typeof(criterion_scores) = 'object'),
    strengths                   JSONB NOT NULL DEFAULT '[]'::JSONB
                                CHECK (jsonb_typeof(strengths) = 'array'),
    missing_or_unclear_items    JSONB NOT NULL DEFAULT '[]'::JSONB
                                CHECK (jsonb_typeof(missing_or_unclear_items) = 'array'),
    evidence                    JSONB NOT NULL DEFAULT '{}'::JSONB
                                CHECK (jsonb_typeof(evidence) = 'object'),
    parsing_warnings            JSONB NOT NULL DEFAULT '[]'::JSONB
                                CHECK (jsonb_typeof(parsing_warnings) = 'array'),
    recommendation              VARCHAR(40) NOT NULL
                                CHECK (recommendation IN (
                                    'RECOMMEND_SCREENING_REVIEW',
                                    'REQUEST_MANUAL_REVIEW',
                                    'INSUFFICIENT_EVIDENCE'
                                )),
    rubric_snapshot             JSONB NOT NULL
                                CHECK (jsonb_typeof(rubric_snapshot) = 'object'),
    model_provider              VARCHAR(100),
    model_name                  VARCHAR(150),
    model_version               VARCHAR(100),
    prompt_version              VARCHAR(100),
    evaluated_at                TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_resume_evaluations_resume_date
    ON resume_evaluations(resume_id, evaluated_at DESC);

-- ---------------------------------------------------------------------------
-- 10. SCREENING_CALLS
-- One row per call attempt. The full transcript/summary belongs to that attempt.
-- Recording/transcript must not be stored when consent was declined.
-- ---------------------------------------------------------------------------
CREATE TABLE screening_calls (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id      UUID NOT NULL REFERENCES applications(id) ON DELETE RESTRICT,
    attempt_number      INTEGER NOT NULL DEFAULT 1 CHECK (attempt_number > 0),
    call_status         VARCHAR(30) NOT NULL DEFAULT 'PENDING'
                        CHECK (call_status IN (
                            'PENDING', 'IN_PROGRESS', 'COMPLETED', 'NO_ANSWER',
                            'FAILED', 'CANCELLED', 'ESCALATED_TO_HUMAN'
                        )),
    consent_status      VARCHAR(20) NOT NULL DEFAULT 'PENDING'
                        CHECK (consent_status IN ('PENDING', 'GRANTED', 'DECLINED', 'NOT_REQUIRED')),
    consent_recorded_at TIMESTAMPTZ,
    transcript_text     TEXT,
    summary             TEXT,
    unresolved_questions JSONB NOT NULL DEFAULT '[]'::JSONB
                        CHECK (jsonb_typeof(unresolved_questions) = 'array'),
    recording_path      TEXT,
    provider_name       VARCHAR(100),
    provider_call_id    VARCHAR(255),
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_screening_attempt UNIQUE (application_id, attempt_number),
    CONSTRAINT ck_screening_consent_before_storage CHECK (
        (transcript_text IS NULL AND recording_path IS NULL)
        OR consent_status IN ('GRANTED', 'NOT_REQUIRED')
    )
);

CREATE INDEX idx_screening_calls_application_id ON screening_calls(application_id);
CREATE INDEX idx_screening_calls_status ON screening_calls(call_status);

-- ---------------------------------------------------------------------------
-- 11. SCREENING_RESPONSES
-- One row per question/answer within a screening attempt. question_text_snapshot
-- preserves the actual wording even if HR later edits the job question.
-- ---------------------------------------------------------------------------
CREATE TABLE screening_responses (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    screening_call_id       UUID NOT NULL REFERENCES screening_calls(id) ON DELETE RESTRICT,
    job_question_id         UUID REFERENCES job_screening_questions(id) ON DELETE SET NULL,
    question_text_snapshot  TEXT NOT NULL,
    answer_text             TEXT,
    answer_status           VARCHAR(20) NOT NULL DEFAULT 'UNANSWERED'
                            CHECK (answer_status IN ('ANSWERED', 'UNCLEAR', 'UNANSWERED', 'DECLINED')),
    question_order          INTEGER NOT NULL CHECK (question_order > 0),
    asked_at                TIMESTAMPTZ,
    answered_at             TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_screening_response_order UNIQUE (screening_call_id, question_order)
);

CREATE INDEX idx_screening_responses_call_id ON screening_responses(screening_call_id);

-- ---------------------------------------------------------------------------
-- 12. CANDIDATE_AVAILABILITY
-- Availability windows provided by the candidate for interview scheduling.
-- Multiple windows can be saved for one application.
-- ---------------------------------------------------------------------------
CREATE TABLE candidate_availability (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id      UUID NOT NULL REFERENCES applications(id) ON DELETE RESTRICT,
    available_from      TIMESTAMPTZ NOT NULL,
    available_to        TIMESTAMPTZ NOT NULL,
    timezone            VARCHAR(100) NOT NULL,
    captured_via        VARCHAR(30) NOT NULL DEFAULT 'MANUAL'
                        CHECK (captured_via IN ('MANUAL', 'SCREENING_CALL', 'AVAILABILITY_FORM')),
    submitted_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_candidate_availability_range CHECK (available_to > available_from)
);

CREATE INDEX idx_candidate_availability_application
    ON candidate_availability(application_id, available_from);

-- ---------------------------------------------------------------------------
-- 13. INTERVIEWER_AVAILABILITY
-- Availability windows from a mock calendar, manual entry or connected calendar.
-- Kept separately so Agent 3 can check interviewer availability before proposing.
-- ---------------------------------------------------------------------------
CREATE TABLE interviewer_availability (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    interviewer_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    available_from      TIMESTAMPTZ NOT NULL,
    available_to        TIMESTAMPTZ NOT NULL,
    timezone            VARCHAR(100) NOT NULL,
    availability_type   VARCHAR(15) NOT NULL
                        CHECK (availability_type IN ('AVAILABLE', 'UNAVAILABLE')),
    source              VARCHAR(20) NOT NULL DEFAULT 'MOCK'
                        CHECK (source IN ('MOCK', 'MANUAL', 'CALENDAR')),
    external_event_id   VARCHAR(255),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_interviewer_availability_range CHECK (available_to > available_from)
);

CREATE INDEX idx_interviewer_availability_user_time
    ON interviewer_availability(interviewer_user_id, available_from, available_to);

-- ---------------------------------------------------------------------------
-- 14. INTERVIEW_SCHEDULES
-- One scheduling attempt/process. Old schedules can remain as history if
-- cancelled/rescheduled; only one active schedule per application is allowed.
-- ---------------------------------------------------------------------------
CREATE TABLE interview_schedules (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id      UUID NOT NULL REFERENCES applications(id) ON DELETE RESTRICT,
    interviewer_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    duration_minutes    INTEGER NOT NULL DEFAULT 45 CHECK (duration_minutes > 0),
    timezone            VARCHAR(100) NOT NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'PROPOSED'
                        CHECK (status IN ('PROPOSED', 'APPROVED', 'SENT', 'CANCELLED', 'COMPLETED', 'FAILED')),
    meeting_link        TEXT,
    meeting_location    TEXT,
    email_subject       TEXT,
    email_body          TEXT,
    approved_by         UUID REFERENCES users(id) ON DELETE RESTRICT,
    approved_at         TIMESTAMPTZ,
    sent_at             TIMESTAMPTZ,
    provider_event_id   VARCHAR(255),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_interview_approval_required CHECK (
        status NOT IN ('APPROVED', 'SENT') OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)
    ),
    CONSTRAINT ck_interview_sent_timestamp CHECK (status <> 'SENT' OR sent_at IS NOT NULL)
);

CREATE UNIQUE INDEX uq_one_active_schedule_per_application
    ON interview_schedules(application_id)
    WHERE status IN ('PROPOSED', 'APPROVED', 'SENT');
CREATE INDEX idx_interview_schedules_application ON interview_schedules(application_id);
CREATE INDEX idx_interview_schedules_interviewer ON interview_schedules(interviewer_user_id);

-- ---------------------------------------------------------------------------
-- 15. INTERVIEW_SLOTS
-- Proposed time options for one scheduling process. At most one slot can be
-- SELECTED for a schedule; only genuinely available slots should be proposed.
-- ---------------------------------------------------------------------------
CREATE TABLE interview_slots (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    interview_schedule_id   UUID NOT NULL REFERENCES interview_schedules(id) ON DELETE RESTRICT,
    start_at                TIMESTAMPTZ NOT NULL,
    end_at                  TIMESTAMPTZ NOT NULL,
    candidate_available     BOOLEAN NOT NULL DEFAULT FALSE,
    interviewer_available   BOOLEAN NOT NULL DEFAULT FALSE,
    availability_source     VARCHAR(20) NOT NULL DEFAULT 'MOCK'
                            CHECK (availability_source IN ('MOCK', 'CALENDAR', 'MANUAL')),
    slot_status             VARCHAR(20) NOT NULL DEFAULT 'PROPOSED'
                            CHECK (slot_status IN ('PROPOSED', 'SELECTED', 'DECLINED', 'EXPIRED')),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_interview_slot_range CHECK (end_at > start_at),
    CONSTRAINT ck_selected_slot_is_available CHECK (
        slot_status <> 'SELECTED' OR (candidate_available = TRUE AND interviewer_available = TRUE)
    ),
    CONSTRAINT uq_interview_slot_time UNIQUE (interview_schedule_id, start_at, end_at)
);

CREATE UNIQUE INDEX uq_one_selected_slot_per_schedule
    ON interview_slots(interview_schedule_id) WHERE slot_status = 'SELECTED';
CREATE INDEX idx_interview_slots_schedule ON interview_slots(interview_schedule_id);

-- ---------------------------------------------------------------------------
-- 16. COMMUNICATION_LOGS
-- Email/SMS/call event metadata and delivery outcomes. Call transcripts remain
-- in screening_calls and are not duplicated here.
-- ---------------------------------------------------------------------------
CREATE TABLE communication_logs (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id          UUID NOT NULL REFERENCES applications(id) ON DELETE RESTRICT,
    interview_schedule_id   UUID REFERENCES interview_schedules(id) ON DELETE RESTRICT,
    screening_call_id       UUID REFERENCES screening_calls(id) ON DELETE RESTRICT,
    communication_type      VARCHAR(20) NOT NULL
                            CHECK (communication_type IN ('EMAIL', 'SMS', 'VOICE_CALL')),
    direction               VARCHAR(10) NOT NULL
                            CHECK (direction IN ('INBOUND', 'OUTBOUND')),
    recipient               VARCHAR(255) NOT NULL,
    sender                  VARCHAR(255),
    subject                 TEXT,
    message_body            TEXT,
    delivery_status         VARCHAR(20) NOT NULL DEFAULT 'PENDING'
                            CHECK (delivery_status IN ('PENDING', 'SENT', 'DELIVERED', 'FAILED', 'BOUNCED')),
    provider_name           VARCHAR(100),
    provider_message_id     VARCHAR(255),
    idempotency_key         VARCHAR(255),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    sent_at                 TIMESTAMPTZ,
    delivered_at            TIMESTAMPTZ
);

CREATE UNIQUE INDEX uq_communication_idempotency_key
    ON communication_logs(idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX idx_communication_logs_application_date
    ON communication_logs(application_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 17. AUDIT_LOGS
-- Append-only history of important user, agent and system actions.
-- Use one of application_id or job_id to identify the affected record.
-- ---------------------------------------------------------------------------
CREATE TABLE audit_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id      UUID REFERENCES applications(id) ON DELETE RESTRICT,
    job_id              UUID REFERENCES jobs(id) ON DELETE RESTRICT,
    actor_type          VARCHAR(10) NOT NULL
                        CHECK (actor_type IN ('USER', 'AGENT', 'SYSTEM')),
    actor_user_id       UUID REFERENCES users(id) ON DELETE RESTRICT,
    actor_name          VARCHAR(150),
    action              VARCHAR(100) NOT NULL,
    previous_status     VARCHAR(50),
    new_status          VARCHAR(50),
    comments            TEXT,
    details             JSONB NOT NULL DEFAULT '{}'::JSONB
                        CHECK (jsonb_typeof(details) = 'object'),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_audit_log_target CHECK (application_id IS NOT NULL OR job_id IS NOT NULL),
    CONSTRAINT ck_audit_log_user_actor CHECK (actor_type <> 'USER' OR actor_user_id IS NOT NULL)
);

CREATE INDEX idx_audit_logs_application_date
    ON audit_logs(application_id, created_at DESC);
CREATE INDEX idx_audit_logs_job_date
    ON audit_logs(job_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- AUTOMATIC updated_at MAINTENANCE
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_jobs_updated_at
BEFORE UPDATE ON jobs
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_job_scoring_criteria_updated_at
BEFORE UPDATE ON job_scoring_criteria
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_job_screening_questions_updated_at
BEFORE UPDATE ON job_screening_questions
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_candidates_updated_at
BEFORE UPDATE ON candidates
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_applications_updated_at
BEFORE UPDATE ON applications
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_interview_schedules_updated_at
BEFORE UPDATE ON interview_schedules
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- IMPORTANT APPLICATION-LEVEL RULES (implemented in FastAPI, not only SQL):
--   * Active scoring criteria weights for a job must add up to 100.
--   * Validate every candidate application status transition before updating.
--   * Write the application status change and its audit_logs row in one DB
--     transaction.
--   * Agent 1 runs only after successful resume extraction and a valid rubric.
--   * Agent 2 runs only after HR sets APPROVED_FOR_SCREENING.
--   * Agent 3 runs only after HR sets APPROVED_FOR_INTERVIEW.
--   * Never send an invitation until HR approval is stored.
--   * Check that the selected slot is available for both candidate and
--     interviewer; re-check immediately before confirmation to avoid conflicts.
--   * Check that interviewer_user_id and approved_by have appropriate roles.
--   * Do not log passwords, API keys, full resumes or unnecessary transcript
--     content in application logs.
--   * Implement a documented retention/deletion process; do not cascade-delete
--     application history as part of ordinary workflow actions.
-- ---------------------------------------------------------------------------

-- End of schema.
