require "test_helper"
require "minitest/mock"

class LabResultImportJobTest < ActiveSupport::TestCase
  test "a fully valid file completes with no errors" do
    import = LabResultImport.create!(filename: "john_doe_hl7.txt", content: file_fixture("john_doe_hl7.txt").read)

    LabResultImportJob.perform_now(import.id.to_s)
    import.reload

    assert_equal "completed", import.status
    assert_empty import.import_errors
    assert_equal 1, Patient.count
    assert_equal 1, Assessment.count
  end

  test "a partially valid file completes with errors" do
    import = LabResultImport.create!(filename: "mixed.txt", content: file_fixture("mixed_valid_and_invalid_hl7.txt").read)

    LabResultImportJob.perform_now(import.id.to_s)
    import.reload

    assert_equal "completed_with_errors", import.status
    assert import.import_errors.present?
    assert Patient.count.positive?
  end

  test "a file with no parseable content fails with zero patients persisted" do
    # Content can't be blank (model validation), so this uses garbage lines
    # that fail every parser line-type check, rather than a literally empty file.
    import = LabResultImport.create!(filename: "garbage.txt", content: "not a valid line at all\nanother garbage line\n")

    LabResultImportJob.perform_now(import.id.to_s)
    import.reload

    assert_equal "failed", import.status
    assert_equal 0, Patient.count
    assert import.import_errors.present?
  end

  test "an unexpected exception marks the import as failed and captures the message" do
    import = LabResultImport.create!(filename: "john_doe_hl7.txt", content: file_fixture("john_doe_hl7.txt").read)

    LabResultParserService.stub(:call, ->(_input) { raise "boom" }) do
      LabResultImportJob.perform_now(import.id.to_s)
    end
    import.reload

    assert_equal "failed", import.status
    assert import.import_errors.any? { |e| (e[:message] || e["message"]).to_s.include?("boom") }
  end
end
