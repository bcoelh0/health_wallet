class LabResultImportJob < ApplicationJob
  def perform(lab_result_import_id)
    record = LabResultImport.find(lab_result_import_id)
    record.update!(status: "processing")

    parsed = LabResultParserService.call(record.content)
    persisted = LabResultPersisterService.call(parsed)

    record.update!(status: determine_status(persisted), import_errors: persisted[:errors])
  rescue StandardError => e
    # Safety net only — both services are resilient and aren't expected to raise.
    # Uses `set` (atomic, skips validations) so this path can't itself fail.
    record&.set(status: "failed", import_errors: (record&.import_errors || []) + [ { line: nil, message: "Unexpected error: #{e.message}" } ])
  end

  private

  def determine_status(persisted)
    return "completed" if persisted[:errors].empty?
    return "failed" if persisted[:patients].empty? # nothing persisted at all
    "completed_with_errors"
  end
end
