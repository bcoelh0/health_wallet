require "test_helper"

class LabResultParserServiceTest < ActiveSupport::TestCase
  def parse_fixture(name)
    LabResultParserService.call(file_fixture(name).read)
  end

  test "parses a single patient with one assessment and multiple observations" do
    result = parse_fixture("john_doe_hl7.txt")

    assert_empty result[:errors]
    assert_equal 1, result[:patients].size

    patient = result[:patients].first
    assert_equal "John Doe", patient[:name]
    assert_equal Date.new(1985, 3, 15), patient[:dob]
    assert_equal "Male", patient[:sex_at_birth]
    assert_equal 1, patient[:assessments].size

    assessment = patient[:assessments].first
    assert_equal "REF-2024-001", assessment[:reference]
    assert_equal 1, assessment[:header_line]

    observations = assessment[:observations]
    assert_equal 4, observations.size
    assert_equal({ code: "8480-6", name: "Blood Pressure (Systolic)", value: 120.0, units: "mmHg", line: 2 }, observations[0])
    assert_equal({ code: "8462-4", name: "Blood Pressure (Diastolic)", value: 80.0, units: "mmHg", line: 3 }, observations[1])
    assert_equal({ code: "8867-4", name: "Heart Rate", value: 72.0, units: "bpm", line: 4 }, observations[2])
    assert_equal({ code: "8310-5", name: "Body Temperature", value: 98.6, units: "°F", line: 5 }, observations[3])
  end

  test "parses multiple distinct patients in file order" do
    result = parse_fixture("multiple_patients_hl7.txt")

    assert_empty result[:errors]
    assert_equal %w[John\ Doe Jane\ Smith Josh\ Brown], result[:patients].map { |p| p[:name] }

    john = result[:patients][0]
    assert_equal "REF-2024-003", john[:assessments][0][:reference]
    assert_equal 1, john[:assessments][0][:observations].size

    jane = result[:patients][1]
    assert_equal "REF-2024-004", jane[:assessments][0][:reference]
    assert_equal 2, jane[:assessments][0][:observations].size

    josh = result[:patients][2]
    assert_equal "REF-2024-005", josh[:assessments][0][:reference]
    assert_equal 2, josh[:assessments][0][:observations].size
  end

  test "groups repeated header blocks for the same patient identity into one patient with multiple assessments" do
    content = <<~HL7
      John Doe|1985-03-15|M|REF-2024-001
      8480-6|120|mmHg
      John Doe|1985-03-15|M|REF-2024-002
      8867-4|72|bpm
    HL7

    result = LabResultParserService.call(content)

    assert_empty result[:errors]
    assert_equal 1, result[:patients].size
    assert_equal %w[REF-2024-001 REF-2024-002], result[:patients].first[:assessments].map { |a| a[:reference] }
  end

  test "malformed header field count is reported and surrounding blocks are unaffected" do
    result = parse_fixture("malformed_header_field_count_hl7.txt")

    assert_equal [ "John Doe", "Josh Brown" ], result[:patients].map { |p| p[:name] }
    assert_equal 1, result[:errors].size
    assert_equal 3, result[:errors].first[:line]
    assert_match(/Malformed line/, result[:errors].first[:message])
  end

  test "invalid date of birth rejects the whole header block" do
    result = parse_fixture("invalid_dob_hl7.txt")

    assert_equal [ "John Doe", "Josh Brown" ], result[:patients].map { |p| p[:name] }
    # The rejected header also resets the current assessment, so the observation
    # line that follows it is correctly reported as an orphan (a second error).
    assert_equal 2, result[:errors].size
    assert_equal 3, result[:errors][0][:line]
    assert_match(/Invalid date of birth/, result[:errors][0][:message])
    assert_equal 4, result[:errors][1][:line]
    assert_match(/before any assessment header/, result[:errors][1][:message])
  end

  test "invalid sex code rejects the whole header block" do
    result = parse_fixture("invalid_sex_code_hl7.txt")

    assert_equal [ "John Doe", "Josh Brown" ], result[:patients].map { |p| p[:name] }
    assert_equal 2, result[:errors].size
    assert_equal 3, result[:errors][0][:line]
    assert_match(/Invalid sex_at_birth code/, result[:errors][0][:message])
    assert_equal 4, result[:errors][1][:line]
    assert_match(/before any assessment header/, result[:errors][1][:message])
  end

  test "blank patient name and blank reference each reject their block" do
    blank_name = LabResultParserService.call("|1985-03-15|M|REF-2024-001\n8480-6|120|mmHg\n")
    assert_empty blank_name[:patients]
    assert_equal 2, blank_name[:errors].size
    assert_match(/Patient name is blank/, blank_name[:errors][0][:message])
    assert_match(/before any assessment header/, blank_name[:errors][1][:message])

    blank_reference = LabResultParserService.call("John Doe|1985-03-15|M|\n8480-6|120|mmHg\n")
    assert_empty blank_reference[:patients]
    assert_equal 2, blank_reference[:errors].size
    assert_match(/Assessment reference is blank/, blank_reference[:errors][0][:message])
    assert_match(/before any assessment header/, blank_reference[:errors][1][:message])
  end

  test "unknown observation code drops only that observation" do
    result = parse_fixture("unknown_observation_code_hl7.txt")

    assert_equal 1, result[:patients].size
    observations = result[:patients].first[:assessments].first[:observations]
    assert_equal %w[8480-6 8462-4], observations.map { |o| o[:code] }

    assert_equal 1, result[:errors].size
    assert_equal 3, result[:errors].first[:line]
    assert_match(/Unknown observation code/, result[:errors].first[:message])
  end

  test "non-numeric observation value drops only that observation" do
    result = parse_fixture("non_numeric_value_hl7.txt")

    assert_equal 1, result[:patients].size
    observations = result[:patients].first[:assessments].first[:observations]
    assert_equal %w[8480-6 8867-4], observations.map { |o| o[:code] }

    assert_equal 1, result[:errors].size
    assert_equal 3, result[:errors].first[:line]
    assert_match(/Non-numeric observation value/, result[:errors].first[:message])
  end

  test "orphan observation line before any header is reported and contributes no patient data" do
    result = parse_fixture("orphan_observation_hl7.txt")

    assert_equal 1, result[:patients].size
    assert_equal 1, result[:patients].first[:assessments].first[:observations].size

    assert_equal 1, result[:errors].size
    assert_equal 1, result[:errors].first[:line]
    assert_match(/before any assessment header/, result[:errors].first[:message])
  end

  test "blank lines are skipped without generating errors" do
    result = parse_fixture("blank_line_hl7.txt")

    assert_empty result[:errors]
    assert_equal 2, result[:patients].first[:assessments].first[:observations].size
  end

  test "empty and nil input return an empty result with a file-level error" do
    empty_result = parse_fixture("empty_file_hl7.txt")
    assert_equal({ patients: [], errors: [ { line: nil, message: "File is empty" } ] }, empty_result)

    nil_result = LabResultParserService.call(nil)
    assert_equal({ patients: [], errors: [ { line: nil, message: "File is empty" } ] }, nil_result)
  end

  test "sex_at_birth is normalized from single-letter codes to full words" do
    result = LabResultParserService.call("John Doe|1985-03-15|M|REF-1\nJane Smith|1990-07-22|F|REF-2\n")

    assert_equal "Male", result[:patients][0][:sex_at_birth]
    assert_equal "Female", result[:patients][1][:sex_at_birth]
  end

  test "every known LOINC code resolves to its correct observation name" do
    LabResultParserService::OBSERVATION_NAMES_BY_CODE.each do |code, name|
      content = "John Doe|1985-03-15|M|REF-1\n#{code}|1|unit\n"
      result = LabResultParserService.call(content)

      assert_equal name, result[:patients].first[:assessments].first[:observations].first[:name]
    end
  end

  test "accepts an IO-like object as well as a raw string" do
    path = file_fixture("john_doe_hl7.txt")
    from_string = LabResultParserService.call(File.read(path))
    from_io = File.open(path) { |file| LabResultParserService.call(file) }

    assert_equal from_string, from_io
  end

  test "mixed valid and invalid content returns both parsed data and errors without raising" do
    result = parse_fixture("mixed_valid_and_invalid_hl7.txt")

    assert_equal %w[John\ Doe Jane\ Smith], result[:patients].map { |p| p[:name] }
    assert_operator result[:errors].size, :>=, 3
  end

  test "does not perform any persistence" do
    assert_equal 0, Patient.count
    assert_equal 0, Assessment.count

    parse_fixture("multiple_patients_hl7.txt")

    assert_equal 0, Patient.count
    assert_equal 0, Assessment.count
  end
end
