--
-- PostgreSQL database dump
--

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: answer_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.answer_keys (
    id uuid NOT NULL,
    exam_id uuid,
    question_number integer NOT NULL,
    correct_answer character varying(5) NOT NULL,
    marks numeric DEFAULT 1,
    negative_marks numeric DEFAULT 0
);


--
-- Name: exam_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exam_results (
    id uuid NOT NULL,
    exam_id uuid,
    scan_id uuid,
    roll_number character varying(100),
    registration_number character varying(100),
    correct integer DEFAULT 0,
    wrong integer DEFAULT 0,
    blank integer DEFAULT 0,
    ambiguous integer DEFAULT 0,
    marks numeric DEFAULT 0,
    percentage numeric DEFAULT 0,
    needs_review boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT now(),
    max_marks numeric,
    grade character varying(10),
    passed boolean
);


--
-- Name: exam_scoring_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exam_scoring_rules (
    exam_id uuid NOT NULL,
    marks_correct numeric DEFAULT 1 NOT NULL,
    marks_wrong numeric DEFAULT '-0.5'::numeric NOT NULL,
    marks_blank numeric DEFAULT 0 NOT NULL,
    pass_percentage numeric DEFAULT 40 NOT NULL,
    ambiguous_as character varying(20) DEFAULT 'review'::character varying NOT NULL,
    clamp_negative_total boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT valid_ambiguous_as CHECK (((ambiguous_as)::text = ANY ((ARRAY['review'::character varying, 'wrong'::character varying, 'blank'::character varying])::text[]))),
    CONSTRAINT valid_marks_blank CHECK ((marks_blank = (0)::numeric)),
    CONSTRAINT valid_marks_correct CHECK ((marks_correct >= (0)::numeric)),
    CONSTRAINT valid_marks_wrong CHECK ((marks_wrong <= (0)::numeric)),
    CONSTRAINT valid_pass_percentage CHECK (((pass_percentage >= (0)::numeric) AND (pass_percentage <= (100)::numeric)))
);


--
-- Name: exams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exams (
    id uuid NOT NULL,
    title character varying(255) NOT NULL,
    subject character varying(255),
    total_questions integer NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    user_id integer
);


--
-- Name: omr_answers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.omr_answers (
    id bigint NOT NULL,
    scan_id uuid NOT NULL,
    question_number integer NOT NULL,
    value text,
    status text NOT NULL,
    confidence numeric,
    scores jsonb DEFAULT '[]'::jsonb NOT NULL
);


--
-- Name: omr_answers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.omr_answers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: omr_answers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.omr_answers_id_seq OWNED BY public.omr_answers.id;


--
-- Name: omr_scans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.omr_scans (
    id uuid NOT NULL,
    source_name text,
    template_id text NOT NULL,
    ok boolean NOT NULL,
    roll_number text,
    registration_number text,
    qr_payload text,
    needs_review boolean DEFAULT false NOT NULL,
    quality jsonb DEFAULT '{}'::jsonb NOT NULL,
    warnings jsonb DEFAULT '[]'::jsonb NOT NULL,
    errors jsonb DEFAULT '[]'::jsonb NOT NULL,
    raw_result jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    exam_id uuid
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    email character varying(255) NOT NULL,
    password_hash text NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: omr_answers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.omr_answers ALTER COLUMN id SET DEFAULT nextval('public.omr_answers_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: answer_keys answer_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.answer_keys
    ADD CONSTRAINT answer_keys_pkey PRIMARY KEY (id);


--
-- Name: exam_results exam_results_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_results
    ADD CONSTRAINT exam_results_pkey PRIMARY KEY (id);


--
-- Name: exam_scoring_rules exam_scoring_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_scoring_rules
    ADD CONSTRAINT exam_scoring_rules_pkey PRIMARY KEY (exam_id);


--
-- Name: exams exams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exams
    ADD CONSTRAINT exams_pkey PRIMARY KEY (id);


--
-- Name: omr_answers omr_answers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.omr_answers
    ADD CONSTRAINT omr_answers_pkey PRIMARY KEY (id);


--
-- Name: omr_answers omr_answers_scan_id_question_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.omr_answers
    ADD CONSTRAINT omr_answers_scan_id_question_number_key UNIQUE (scan_id, question_number);


--
-- Name: omr_scans omr_scans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.omr_scans
    ADD CONSTRAINT omr_scans_pkey PRIMARY KEY (id);


--
-- Name: answer_keys unique_exam_question; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.answer_keys
    ADD CONSTRAINT unique_exam_question UNIQUE (exam_id, question_number);


--
-- Name: exam_results unique_exam_result_scan; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_results
    ADD CONSTRAINT unique_exam_result_scan UNIQUE (scan_id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_exams_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_exams_user_id ON public.exams USING btree (user_id);


--
-- Name: answer_keys answer_keys_exam_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.answer_keys
    ADD CONSTRAINT answer_keys_exam_id_fkey FOREIGN KEY (exam_id) REFERENCES public.exams(id) ON DELETE CASCADE;


--
-- Name: exam_results exam_results_exam_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_results
    ADD CONSTRAINT exam_results_exam_id_fkey FOREIGN KEY (exam_id) REFERENCES public.exams(id) ON DELETE CASCADE;


--
-- Name: exam_results exam_results_scan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_results
    ADD CONSTRAINT exam_results_scan_id_fkey FOREIGN KEY (scan_id) REFERENCES public.omr_scans(id) ON DELETE CASCADE;


--
-- Name: exam_scoring_rules exam_scoring_rules_exam_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exam_scoring_rules
    ADD CONSTRAINT exam_scoring_rules_exam_id_fkey FOREIGN KEY (exam_id) REFERENCES public.exams(id) ON DELETE CASCADE;


--
-- Name: exams exams_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exams
    ADD CONSTRAINT exams_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: omr_answers omr_answers_scan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.omr_answers
    ADD CONSTRAINT omr_answers_scan_id_fkey FOREIGN KEY (scan_id) REFERENCES public.omr_scans(id) ON DELETE CASCADE;


--
-- Name: omr_scans omr_scans_exam_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.omr_scans
    ADD CONSTRAINT omr_scans_exam_id_fkey FOREIGN KEY (exam_id) REFERENCES public.exams(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

