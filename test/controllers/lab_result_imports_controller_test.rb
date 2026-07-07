require "test_helper"

class LabResultImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @lab_result_import = LabResultImport.create!(
      filename: "john_doe_hl7.txt",
      content: file_fixture("john_doe_hl7.txt").read,
      status: "completed",
      summary: { "patients_created" => 1 }
    )
  end

  test "should get index" do
    get lab_result_imports_url
    assert_response :success
    assert_match @lab_result_import.filename, response.body
  end

  test "should get new" do
    get new_lab_result_import_url
    assert_response :success
  end

  test "should show lab result import" do
    get lab_result_import_url(@lab_result_import)
    assert_response :success
    assert_match "Completed", response.body
  end

  test "create with a valid uploaded file creates a pending import and enqueues the job" do
    file = fixture_file_upload("john_doe_hl7.txt", "text/plain")

    assert_difference "LabResultImport.count", 1 do
      assert_enqueued_with(job: LabResultImportJob) do
        post lab_result_imports_url, params: { lab_result_import: { file: file } }
      end
    end

    created = LabResultImport.order(created_at: :desc).first
    assert_equal "pending", created.status
    assert_equal "john_doe_hl7.txt", created.filename
    assert_redirected_to lab_result_import_path(created)
  end

  test "create with no file re-renders new with unprocessable_entity and enqueues nothing" do
    assert_no_difference "LabResultImport.count" do
      assert_no_enqueued_jobs do
        post lab_result_imports_url, params: { lab_result_import: { file: "" } }
      end
    end

    assert_response :unprocessable_entity
  end
end
