1. Parser service (app/services/lab_result_parser_service.rb)
Reads the pipe-delimited HL7-style file format and returns a plain hash of patients → assessments → observations, plus a list of line-numbered errors. Never raises — invalid lines (bad codes, malformed rows, bad dates) are skipped and recorded instead of failing the whole file. Includes the LOINC code → name lookup table and normalizes M/F to Male/Female.

2. Persister service (app/services/lab_result_persister_service.rb)
Takes the parser's output and writes it to the database: finds-or-creates Patient (by name+dob+sex), finds-or-creates Assessment (by reference within patient), finds-or-updates/creates Observation (by code within assessment, updating value/units on match). Idempotent — re-importing the same data doesn't duplicate records.

3. Tracking model + background job (app/models/lab_result_import.rb, app/jobs/lab_result_import_job.rb)
A new LabResultImport Mongoid document stores the uploaded file's content, status, errors, and a summary of what was created/updated. LabResultImportJob runs the parse → persist pipeline against it and settles the status to completed, completed_with_errors, or failed depending on the outcome.

4. Upload UI (app/controllers/lab_result_imports_controller.rb, app/views/lab_result_imports/*, routes, CSS)
A new /lab_result_imports page lets users upload a file, see it queued, and watch the status page auto-refresh until the import finishes — showing counts of records created/updated and a table of any errors. Linked from the home page.

Tests: 49 tests total across services, model, job, and controller, plus fixture files covering every validation-error case in the parser. All passing.

Key decisions made along the way: no ActiveStorage/ActiveRecord introduced (app is Mongoid-only, so the upload is stored as a Mongoid document instead); 5 status states instead of the spec's literal 3, to distinguish a fully failed import from a partially successful one; the job is only ever passed the import's id, never a raw file or record, for safe serialization; status feedback uses a plain meta-refresh tag rather than new websocket/Turbo Streams plumbing.