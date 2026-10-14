"""Generate the Member 5 report section as a Word document.

The prose lives here so the .docx can be regenerated after any wording change.
Citation style is Harvard (author-date), which is the UTS default.
"""

from docx import Document
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Pt, Cm
from docx.oxml.ns import qn

from pathlib import Path

# Write the document next to this script, not into the module directory: the
# generated .docx is not part of the repository.
MODULE_DIR = Path(__file__).resolve().parents[2] / "advanced-database-assignment2" / "sql" / "guanbo"
OUT = Path(__file__).resolve().parent / "out" / "REPORT_SECTION_MEMBER5.docx"
OUT.parent.mkdir(parents=True, exist_ok=True)
doc = Document()

# Base style: Times New Roman 12pt is the usual report default.
style = doc.styles["Normal"]
style.font.name = "Times New Roman"
style.font.size = Pt(11)
style.paragraph_format.space_after = Pt(6)
style.paragraph_format.line_spacing = 1.15
# Long object names must be able to wrap inside table cells.
style.paragraph_format.word_wrap = True

# Page setup: A4 with 2.54 cm margins gives 15.9 cm of text width, which is what
# the table widths below are sized against. The python-docx default template is
# US Letter with wider margins and would clip every table.
from docx.shared import Cm as _Cm

section = doc.sections[0]
section.page_width = _Cm(21.0)
section.page_height = _Cm(29.7)
section.left_margin = _Cm(2.54)
section.right_margin = _Cm(2.54)
section.top_margin = _Cm(2.54)
section.bottom_margin = _Cm(2.54)
for level, size in ((1, 16), (2, 14), (3, 12)):
    heading = doc.styles[f"Heading {level}"]
    heading.font.name = "Times New Roman"
    heading.font.size = Pt(size)
    heading.font.color.rgb = None


def para(text, style_name=None):
    p = doc.add_paragraph(text, style=style_name)
    return p


def bullet(text):
    return doc.add_paragraph(text, style="List Bullet")


def numbered(text):
    return doc.add_paragraph(text, style="List Number")


def table(headers, rows, widths=None):
    t = doc.add_table(rows=1, cols=len(headers))
    t.style = "Light Grid Accent 1"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    for i, header in enumerate(headers):
        cell = t.rows[0].cells[i]
        cell.text = ""
        run = cell.paragraphs[0].add_run(header)
        run.bold = True
        run.font.size = Pt(10)
    for row in rows:
        cells = t.add_row().cells
        for i, value in enumerate(row):
            cells[i].text = ""
            run = cells[i].paragraphs[0].add_run(str(value))
            run.font.size = Pt(10)
    if widths:
        # Autofit lets a renderer widen columns to fit content, which pushes the
        # table past the page margin. Fix the layout and pin every cell width so
        # the total stays inside the text width.
        t.autofit = False
        tblPr = t._tbl.tblPr
        layout = tblPr.find(qn("w:tblLayout"))
        if layout is None:
            layout = tblPr.makeelement(qn("w:tblLayout"), {})
            tblPr.append(layout)
        layout.set(qn("w:type"), "fixed")
        for row in t.rows:
            for i, width in enumerate(widths):
                row.cells[i].width = Cm(width)
        for i, width in enumerate(widths):
            t.columns[i].width = Cm(width)
    doc.add_paragraph()
    return t


def caption(text):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.italic = True
    run.font.size = Pt(10)
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    return p


# ---------------------------------------------------------------------------
doc.add_heading("KYC/AML Exception Detection and Reporting (Member 5)", level=1)

para(
    "This section documents the KYC/AML exception module, which is the compliance "
    "component of the customer integration platform. It explains the business problem "
    "the module solves, the data structures it owns, the validation rules it applies, "
    "how a detected issue becomes a trackable case and a reported exception, and how "
    "the implementation was verified. All figures quoted here were produced by "
    "executing the module against a PostgreSQL engine; the harness that produces them "
    "is described in Section 5."
)

# ---------------------------------------------------------------------------
doc.add_heading("1. Purpose and Position in the Architecture", level=2)

para(
    "The platform consolidates customer data from three operational systems: CRM "
    "banking, lending, and AML/KYC. Each system represents the same person with "
    "different identifiers, so identity resolution is required before a single "
    "customer view exists. Compliance work cannot wait for that resolution to "
    "complete, however: a lapsed identity check or a sanctions alert is a regulatory "
    "matter in its own right, and the report requires that such events remain "
    "reportable while the customer identity is still unresolved."
)

para(
    "The module therefore treats compliance activity as two distinct concepts that the "
    "literature on data provenance also separates: the event that occurred, and the "
    "investigation that follows from it (Cheney, Chiticariu and Tan 2009). An event is "
    "an immutable record that something happened. A case is a unit of work with an "
    "owner, a status and an outcome. Keeping them apart is what allows the platform to "
    "retain complete history without inflating the count of outstanding exceptions."
)

para(
    "The module occupies the compliance domain of the Silver layer and owns the "
    "compliance fact in the Gold layer. It reads Bronze records produced by the "
    "ingestion component and publishes validated events, cases and exceptions "
    "downstream. It does not modify any table owned by another component."
)

caption(
    "Table 1. Position of the module: what it reads, what it owns, and what it publishes."
)
table(
    ["Layer", "Object", "Ownership in this module"],
    [
        ["Bronze", "raw_kyc_verification, raw_aml_screening, raw_aml_kyc_customer", "Read only. Append-only landing data owned by the ingestion component."],
        ["Silver", "kyc_verification_record, aml_screening_result", "Created and published. One row per validation or screening event."],
        ["Silver", "special_verification_case, aml_case", "Created and published. One row per investigation."],
        ["Silver", "data_quality_issue, data_lineage_record", "Written only. Shared control tables owned by the security and audit component."],
        ["Gold", "fact_compliance_exception", "Created and published. One accumulating row per reported exception."],
        ["Gold", "dim_customer", "Read only. Used to attach a customer surrogate key when one exists."],
    ],
    widths=[2.2, 5.7, 7.5],
)

# ---------------------------------------------------------------------------
doc.add_heading("2. Data Structures", level=2)

para(
    "The module owns four Silver tables and one Gold fact table, and exposes three "
    "reporting views. Event tables and case tables are deliberately separate, and the "
    "distinction is the central design decision of the module."
)

doc.add_heading("2.1 Event tables", level=3)

para(
    "silver.kyc_verification_record stores one row per identity verification, and "
    "silver.aml_screening_result stores one row per screening against a sanctions, "
    "politically exposed person (PEP), watchlist or adverse media list. Both are "
    "append-only in business terms: a customer verified three times produces three "
    "rows, because each verification is a separate fact with its own date, result and "
    "expiry. Earlier outcomes are retained rather than overwritten, which is what "
    "allows the platform to demonstrate that a check is or is not still reusable."
)

para(
    "The business key of each event is the source system together with the source "
    "reference, and both tables carry a unique index on that pair. This makes repeated "
    "processing idempotent at the storage level rather than relying on application "
    "logic. Each event must resolve to a subject: either an integrated customer or a "
    "retained source customer record, and if both are present they must agree. A "
    "screening result is explicitly not a confirmed finding; the model records the "
    "similarity score and whether review is required, and treats the alert as a signal "
    "to investigate."
)

doc.add_heading("2.2 Case tables", level=3)

para(
    "silver.special_verification_case records an investigation of a KYC problem, and "
    "silver.aml_case records an investigation of a money laundering or sanctions "
    "concern. The report fixes the verification case types to KYC_GAP, "
    "IDENTITY_MISMATCH and STATUS_DISCREPANCY, and the module enforces that set with a "
    "check constraint so no code path can introduce another value."
)

para(
    "A case may reference an unresolved source customer record, which is how the module "
    "satisfies the requirement that unresolved identities remain reportable. A case "
    "must carry at least one subject or trigger reference, excluding the assignee, and "
    "its status must agree with its closing timestamp: a resolved or closed case "
    "requires a resolution time, and an active case must not carry one. Both rules are "
    "check constraints rather than procedure logic, so they hold regardless of which "
    "code path writes the row."
)

doc.add_heading("2.3 The compliance exception fact", level=3)

para(
    "gold.fact_compliance_exception is an accumulating snapshot fact. Each row "
    "represents one originating case rather than one reporting period, and an open "
    "exception is updated in place on each refresh rather than appended. This is what "
    "lets the exception report answer how long an issue has been outstanding, which a "
    "periodic snapshot cannot express without reconstructing the history."
)

para(
    "Three integrity rules define the fact. Exactly one of verification_case_id and "
    "aml_case_id is populated, and it must agree with exception_source_type; this is "
    "enforced by a check constraint. Each originating case appears at most once, which "
    "is enforced by two partial unique indexes. The customer surrogate key may be null, "
    "because a case whose identity is unresolved still has to be reported, and the "
    "report reaches such rows through a left join rather than discarding them."
)

para(
    "A practical defect was found here during testing and is worth recording, because "
    "it would not have been visible to any static review. The shared schema had "
    "declared the two case-reference indexes as ordinary unique indexes. PostgreSQL "
    "treats null values as distinct in a unique index, and each fact row leaves one of "
    "the two references null, so every row after the first of each kind collided on the "
    "index and the refresh failed. The indexes were redefined as partial unique indexes "
    "that exclude nulls, which preserves the intended rule that each case occurs once."
)

caption("Table 2. Objects owned by the module.")
table(
    ["Object", "Type", "Grain and purpose"],
    [
        ["silver.kyc_verification_record", "Table", "One identity verification event per source reference."],
        ["silver.aml_screening_result", "Table", "One screening event per source reference."],
        ["silver.special_verification_case", "Table", "One KYC investigation, typed KYC_GAP, IDENTITY_MISMATCH or STATUS_DISCREPANCY."],
        ["silver.aml_case", "Table", "One AML investigation, opened from an alert or another documented trigger."],
        ["gold.fact_compliance_exception", "Table", "One accumulating row per originating case."],
        ["gold.vw_kyc_aml_exception_report", "View", "One row per exception with its originating case detail."],
        ["gold.vw_compliance_exception_summary", "View", "Exception counts and longest duration per customer and type."],
        ["silver.vw_kyc_aml_exception_lineage", "View", "Traceability from the raw record through the event and case to the exception."],
    ],
    widths=[5.6, 1.8, 8.0],
)

# ---------------------------------------------------------------------------
doc.add_heading("3. Validation Rules and Case Processing", level=2)

doc.add_heading("3.1 Rule set", level=3)

para(
    "The module implements eighteen validation rules: eight over KYC verification "
    "events and ten over AML screening events. Each rule yields at most one finding per "
    "event, chosen by a fixed ordering of rule priority, severity and rule name, so a "
    "record that breaches several rules is reported once at its most serious finding "
    "rather than several times. Both event types share the same ordering expression, "
    "which prevents the two rule groups from drifting apart."
)

para(
    "Severity carries operational meaning. A finding marked BLOCKING prevents the "
    "affected event from being published to Silver at all, because an event that cannot "
    "be attributed to a subject cannot be reported. Every other finding is reportable: "
    "the event is published, the finding is retained as a data quality issue, and a "
    "case is opened when the rule maps to one."
)

caption("Table 3. Rule-to-case-type mapping for the reportable rules.")
table(
    ["Rule", "Finding", "Case type", "Severity"],
    [
        ["KYC_VERIFICATION_INCOMPLETE", "The check did not complete", "KYC_GAP", "MEDIUM"],
        ["KYC_VERIFICATION_EXPIRED", "The check has lapsed at the reference date", "STATUS_DISCREPANCY", "HIGH"],
        ["KYC_VERIFICATION_STATUS_DISCREPANCY", "Successful status that cannot be relied on", "STATUS_DISCREPANCY", "HIGH"],
        ["KYC_IDENTITY_LINK_MISMATCH", "Event links two different identities", "IDENTITY_MISMATCH", "HIGH"],
        ["AML_REVIEW_REQUIRED", "An alert that requires investigation", "AML_SCREENING_REVIEW", "MEDIUM"],
        ["AML_REVIEW_FLAG_INCONSISTENT", "Alert raised without requiring review", "STATUS_DISCREPANCY", "HIGH"],
    ],
    widths=[6.0, 5.2, 2.8, 1.4],
)

para(
    "Two design points are worth drawing out. First, the mapping from rule to case type "
    "is centralised in a single database function, so the reporting convention required "
    "by the report is expressed in one place and a change of convention does not touch "
    "rule logic. Second, a rule that is not reportable returns no case type and remains "
    "a quality record. The unresolved-identity notice is deliberately in this category: "
    "an identity that is still pending is information the report should show, but it is "
    "not itself a compliance exception, and treating it as one would overstate the "
    "exception count."
)

doc.add_heading("3.2 Case reuse and status progression", level=3)

para(
    "The report requires that repeated findings for the same customer or natural source "
    "identity and issue type reuse an existing open case rather than creating another. "
    "The module implements this by deriving the case identifier from the event and the "
    "case type, and by searching for an existing case for the same subject and type "
    "before inserting. The consequence is that a case count is a count of problems, not "
    "a count of detections, and that a case identifier is stable across reruns."
)

para(
    "Case status is then reconciled against current evidence rather than stored as an "
    "independent flag. A finding that the rules no longer produce is resolved; a "
    "verification case whose last open finding has cleared becomes RESOLVED with a "
    "recorded outcome; an AML case whose alert no longer stands becomes CLOSED. A case "
    "that still has an open finding stays open, so its age continues to accumulate "
    "instead of being closed and reopened. This matters for the exception report, "
    "because a reopened case would reset the age of an issue that is in fact still "
    "outstanding."
)

doc.add_heading("3.3 Exception reporting and KYC status", level=3)

para(
    "gold.refresh_compliance_exception_fact consolidates both case families into the "
    "accumulating fact. The elapsed-days measure counts calendar days from the opening "
    "date to the closing date, or to the reporting date while the case is open, and it "
    "is capped at the reporting date. The cap is a deliberate semantic choice: an "
    "exception cannot have been open for longer than the reporting period, and without "
    "the cap a case closed after the reporting cut-off would be reported with an age "
    "beyond the period it belongs to. The true closing date is still recorded for "
    "audit purposes."
)

para(
    "Two reporting views sit over the fact. The exception report presents one row per "
    "exception with the originating case detail and retains rows whose identity is "
    "unresolved. The summary view aggregates counts, open and resolved subtotals, the "
    "longest duration and the highest severity per customer and exception type; the "
    "highest severity is selected through an explicit severity ranking, because taking "
    "the alphabetically largest label would rank MEDIUM above HIGH. A third view exposes "
    "the lineage chain so that any reported exception can be traced back to the raw "
    "Bronze record that produced it (Cheney, Chiticariu and Tan 2009)."
)

para(
    "The report also defines the circumstances under which a KYC check is considered "
    "reusable, and requires a customer-level status derived from that rule. The module "
    "exposes this as a table function that evaluates a customer at a given reference "
    "date: a customer is VERIFIED only when at least one check is successful and "
    "unexpired and no relevant case is open; if a case is open the status is "
    "REVIEW_REQUIRED, if checks exist but none is reusable it is INCOMPLETE, and if "
    "there is neither a check nor an alert the status is UNKNOWN. Encoding the rule as "
    "a function evaluated at a supplied date, rather than a stored column, keeps the "
    "status reproducible at any reporting cut-off."
)

# ---------------------------------------------------------------------------
doc.add_heading("4. Implementation Approach", level=2)

para(
    "The module is implemented as nine SQL scripts executed in filename order, followed "
    "by a pipeline of five procedure calls per batch. It comprises five tables, three "
    "views, thirteen functions, eight procedures, twenty check constraints and six "
    "indexes."
)

caption("Table 4. Scripts in execution order.")
table(
    ["Script", "Responsibility"],
    [
        ["00_add_compliance_constraints", "Check constraints and supporting indexes"],
        ["01_seed_kyc_aml_bronze", "Bronze and control-row seed data for the supplied batches"],
        ["02_load_kyc_aml_dimensions", "Minimal customer identity for the events this module owns"],
        ["03_create_kyc_aml_load_procedures", "Bronze to Silver publication and lineage"],
        ["04_create_kyc_aml_validation", "The eighteen validation rules and finding registration"],
        ["05_create_case_processing", "Case reuse, publication and status progression"],
        ["06_create_exception_fact", "The accumulating exception fact and its refresh"],
        ["07_create_compliance_reporting_views", "Exception report, summary, lineage and KYC status"],
        ["08_validation_tests", "Fifteen acceptance assertions and report-ready queries"],
    ],
    widths=[6.6, 8.8],
)

para(
    "Three properties of the implementation are relevant to the report's quality "
    "requirements. First, every write is idempotent: primary keys are derived from "
    "business keys, inserts use conflict handling, and temporary staging tables are "
    "recreated per run, so the whole pipeline can be executed repeatedly without "
    "duplicating data. This was confirmed by an assertion that reruns the case "
    "publication and batch processing and checks that row counts do not change."
)

para(
    "Second, the module is isolated from the components it depends on. It reads Bronze "
    "without modifying it, and it creates only the customer identity that its own events "
    "reference, leaving any identity already resolved by the identity resolution "
    "component untouched. It also does not require the ingestion component to have "
    "succeeded: a batch that the ingestion component leaves failed still retains its raw "
    "rows in Bronze, and this module processes them from there. That case is present in "
    "the supplied data and its compliance exception is reported, which demonstrates that "
    "a failed upstream validation does not silently remove a regulatory obligation."
)

para(
    "Third, lineage is written as part of publication rather than reconstructed "
    "afterwards. Each published event produces a lineage record linking the Bronze "
    "record to the Silver event, which is what the traceability view reads. Recording "
    "provenance at the point of transformation is the approach the provenance literature "
    "recommends, because reconstructing it later requires assumptions that the data may "
    "no longer support (Cheney, Chiticariu and Tan 2009)."
)

# ---------------------------------------------------------------------------
doc.add_heading("5. Verification", level=2)

para(
    "Verification was performed in two layers, because the two answer different "
    "questions. Static parsing establishes that every script is syntactically valid "
    "PostgreSQL (Darafei Praliaskouski 2024). Dynamic execution establishes that the "
    "rules, constraints and procedures behave as intended, which parsing alone cannot "
    "show, since a function body is not validated until it runs. The dynamic layer uses "
    "PGlite, a distribution of PostgreSQL compiled to WebAssembly, so the module was "
    "exercised against the real database engine and not a simulation (ElectricSQL 2025). "
    "The harness is retained in the repository and can be rerun with a single command."
)

para(
    "Executing the module revealed seven defects that static review had not detected. "
    "They are listed in Table 5 because the pattern is itself a finding: each one was a "
    "semantic error inside a procedural body or a storage-level constraint interaction, "
    "precisely the class of problem that parsing cannot reach."
)

caption("Table 5. Defects found by executing the module against a PostgreSQL engine.")
table(
    ["Defect", "Consequence if undetected", "Correction"],
    [
        ["Shared fact indexes declared as ordinary unique indexes", "The exception fact accepted one row per case family, so the second exception failed the refresh", "Redefined as partial unique indexes excluding nulls"],
        ["Procedure invoked with PERFORM inside a procedure", "KYC events were never published; the failure was reported only as a notice", "Corrected to CALL"],
        ["Column alias referenced within its own select list", "The AML rule function would not compile", "Flags computed in a preceding common table expression"],
        ["Expiry rule could not fire for a record already flagged expired", "A lapsed verification produced no status discrepancy, so a required exception was missing", "Rule conditions restated around the reference date"],
        ["Seed guard coupled two batches together", "Nine KYC events were never loaded into Bronze", "Per-batch guard predicates"],
        ["UTF-8 byte order mark written into three scripts", "PostgreSQL rejected the file at its first character", "Byte order mark stripped and prevented by an encoding gate"],
        ["Elapsed days exceeded the reporting period", "An exception closed after the cut-off was reported as older than the report itself", "Duration capped at the reporting date"],
    ],
    widths=[5.0, 6.4, 4.0],
)

para(
    "The module's own acceptance script asserts the business outcome on the supplied "
    "synthetic data at a reference date of 30 September 2026. The results are shown in "
    "Table 6 and Table 7. They are quoted as measured values rather than expected "
    "values, because the same assertions run on every execution and fail the run if the "
    "outcome changes."
)

caption("Table 6. Pipeline results on the supplied data.")
table(
    ["Measure", "Result"],
    [
        ["KYC verification events published to Silver", "9"],
        ["AML screening events published to Silver", "10"],
        ["Validation findings registered", "3"],
        ["Verification cases opened", "2"],
        ["AML cases opened", "1"],
        ["Compliance exception fact rows", "3"],
    ],
    widths=[10.4, 5.0],
)

caption("Table 7. Reported exceptions and the customer-level KYC status derived from them.")
table(
    ["Customer", "Source", "Exception type", "Status", "Severity", "Age (days)"],
    [
        ["Noah Chen", "Verification", "KYC_GAP", "OPEN", "MEDIUM", "29"],
        ["Leo Martin", "Verification", "STATUS_DISCREPANCY", "OPEN", "HIGH", "29"],
        ["Olivia Brooks", "AML", "AML_SCREENING_REVIEW", "CLOSED", "MEDIUM", "15"],
    ],
    widths=[2.8, 2.5, 4.1, 2.0, 2.0, 2.0],
)

para(
    "The three exceptions correspond to three deliberate scenarios in the supplied "
    "data: a missing identity document, a verification that lapsed before the reference "
    "date, and a watchlist screening that returned a potential match with a similarity "
    "score of 0.92. The customer-level KYC status derived from these results is seven "
    "customers VERIFIED and two REVIEW_REQUIRED; no customer with an open exception is "
    "reported as VERIFIED, which is the behaviour the report's KYC status rule requires."
)

# ---------------------------------------------------------------------------
doc.add_heading("6. Limitations", level=2)

para(
    "The module is a batch prototype and does not claim production characteristics. "
    "Screening is simulated from supplied extracts rather than obtained from a screening "
    "provider, so match scores are synthetic. Case assignment is modelled but not "
    "automated, and no case currently carries an assignee. The reference date is passed "
    "as a procedure parameter, which makes the reporting cut-off explicit and "
    "reproducible but requires the caller to supply it. Where an upstream batch has "
    "failed, this module processes the retained Bronze rows; the module therefore reports "
    "compliance exceptions that upstream validation has not yet certified, which is a "
    "deliberate trade-off in favour of regulatory completeness over pipeline tidiness."
)

# ---------------------------------------------------------------------------
doc.add_heading("References", level=2)

refs = [
    "Cheney, J, Chiticariu, L & Tan, W-C 2009, 'Provenance in databases: why, how, and where', "
    "Foundations and Trends in Databases, vol. 1, no. 4, pp. 379-474.",
    "Darafei Praliaskouski 2024, pglast: PostgreSQL Languages AST and statements prettifier, "
    "version 7, viewed 12 October 2026, <https://pglast.readthedocs.io/>.",
    "ElectricSQL 2025, PGlite: PostgreSQL in WebAssembly, viewed 12 October 2026, "
    "<https://electric-sql.com/primitives/pglite>.",
    "PostgreSQL Global Development Group 2024, PostgreSQL 15 documentation, viewed 12 October 2026, "
    "<https://www.postgresql.org/docs/15/>.",
]
for reference in refs:
    p = doc.add_paragraph(reference)
    p.paragraph_format.left_indent = Cm(1.0)
    p.paragraph_format.first_line_indent = Cm(-1.0)

doc.save(OUT)
print(f"written: {OUT}")
