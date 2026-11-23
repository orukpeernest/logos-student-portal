# LOGOS Test Driller question upload format

The Test Mode upload file is separate from the general Practice Question Bank.

Upload a UTF-8 JSON file containing a top-level `questions` array. Each question must have:
- `question_text` (or `question`)
- `option_a`, `option_b`, `option_c`, `option_d` (or an `options` object with A-D)
- `correct_answer` (A, B, C or D)
- `subject` (may be supplied once by the assessment form in a later workflow)

Optional fields: `topic`, `exam_type`, `exam_year`, `explanation`, and an HTTPS `image_url`.

Example:

```json
{
  "questions": [
    {
      "subject": "Physics",
      "topic": "Motion",
      "question_text": "Which quantity is measured in metres per second?",
      "option_a": "Acceleration",
      "option_b": "Velocity",
      "option_c": "Force",
      "option_d": "Energy",
      "correct_answer": "B",
      "explanation": "Velocity is measured in metres per second."
    }
  ]
}
```

Every question imported through the Test Mode upload path is forced to `is_practice: false`. It is saved as an exam-only question and attached to the selected draft assessment. It is not added to the Practice Question Bank.

The upload flow must only attach questions while the assessment remains in draft status. Release is a separate administrator action. Students must not receive questions until the assessment has been released and they explicitly use **UPDATE TEST QUESTIONS**.

## Backend capabilities still required

The current Supabase schema/RPCs inspected so far do not yet persist academic session, assessment availability window, or a server-authoritative start/expiry timestamp per student attempt. Nor do they provide an atomic bulk-upload RPC. These must be added and tested before this workflow can be considered production-ready. The browser countdown is only a display; server-side expiry and automatic submission must be authoritative.
