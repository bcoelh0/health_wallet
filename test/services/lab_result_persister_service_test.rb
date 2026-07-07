require "test_helper"
require "minitest/mock"

class LabResultPersisterServiceTest < ActiveSupport::TestCase
  test "creates new patient, assessment, and observations from scratch" do
    parsed = {
      patients: [
        {
          name: "John Doe", dob: Date.new(1985, 3, 15), sex_at_birth: "Male",
          assessments: [
            {
              reference: "REF-2024-001", header_line: 1,
              observations: [
                { code: "8480-6", name: "Blood Pressure (Systolic)", value: 120.0, units: "mmHg", line: 2 },
                { code: "8462-4", name: "Blood Pressure (Diastolic)", value: 80.0, units: "mmHg", line: 3 }
              ]
            }
          ]
        }
      ],
      errors: []
    }

    result = LabResultPersisterService.call(parsed)

    assert_equal 1, Patient.count
    assert_equal 1, Assessment.count

    patient_entry = result[:patients].first
    assert patient_entry[:created]
    assert_equal "John Doe", patient_entry[:record].name
    assert_equal Date.new(1985, 3, 15), patient_entry[:record].dob
    assert_equal "Male", patient_entry[:record].sex_at_birth

    assessment_entry = patient_entry[:assessments].first
    assert assessment_entry[:created]
    assert_equal "REF-2024-001", assessment_entry[:record].reference

    observation_entries = assessment_entry[:observations]
    assert_equal 2, observation_entries.size
    assert observation_entries.all? { |o| o[:created] }
    assert_equal [ "8480-6", "8462-4" ], observation_entries.map { |o| o[:record].code }
  end

  test "reuses an existing patient matched by name, dob, and sex_at_birth" do
    existing_patient = Patient.create!(name: "John Doe", dob: Date.new(1985, 3, 15), sex_at_birth: "Male")

    parsed = {
      patients: [
        {
          name: "John Doe", dob: Date.new(1985, 3, 15), sex_at_birth: "Male",
          assessments: [ { reference: "REF-NEW", header_line: 1, observations: [] } ]
        }
      ],
      errors: []
    }

    result = LabResultPersisterService.call(parsed)

    assert_equal 1, Patient.count
    patient_entry = result[:patients].first
    refute patient_entry[:created]
    assert_equal existing_patient.id, patient_entry[:record].id
    assert_equal 1, patient_entry[:record].assessments.count
  end

  test "reuses an existing assessment matched by reference within the patient" do
    patient = Patient.create!(name: "John Doe", dob: Date.new(1985, 3, 15), sex_at_birth: "Male")
    existing_assessment = patient.assessments.create!(reference: "REF-2024-001")

    parsed = {
      patients: [
        {
          name: "John Doe", dob: Date.new(1985, 3, 15), sex_at_birth: "Male",
          assessments: [
            {
              reference: "REF-2024-001", header_line: 1,
              observations: [ { code: "8867-4", name: "Heart Rate", value: 72.0, units: "bpm", line: 2 } ]
            }
          ]
        }
      ],
      errors: []
    }

    result = LabResultPersisterService.call(parsed)

    assert_equal 1, Assessment.count
    assessment_entry = result[:patients].first[:assessments].first
    refute assessment_entry[:created]
    assert_equal existing_assessment.id, assessment_entry[:record].id
    assert_equal 1, assessment_entry[:record].observations.count
  end

  test "updates value and units of an existing observation but leaves name unchanged" do
    patient = Patient.create!(name: "John Doe", dob: Date.new(1985, 3, 15), sex_at_birth: "Male")
    assessment = patient.assessments.create!(reference: "REF-2024-001")
    assessment.observations.create!(name: "Blood Pressure (Systolic)", code: "8480-6", value: 100.0, units: "mmHg")

    parsed = {
      patients: [
        {
          name: "John Doe", dob: Date.new(1985, 3, 15), sex_at_birth: "Male",
          assessments: [
            {
              reference: "REF-2024-001", header_line: 1,
              observations: [ { code: "8480-6", name: "Different Name", value: 125.0, units: "kPa", line: 2 } ]
            }
          ]
        }
      ],
      errors: []
    }

    result = LabResultPersisterService.call(parsed)

    assessment.reload
    assert_equal 1, assessment.observations.count

    observation = assessment.observations.first
    assert_equal 125.0, observation.value
    assert_equal "kPa", observation.units
    assert_equal "Blood Pressure (Systolic)", observation.name

    observation_entry = result[:patients].first[:assessments].first[:observations].first
    refute observation_entry[:created]
  end

  test "re-running the persister on the same parsed hash is idempotent" do
    parsed = {
      patients: [
        {
          name: "John Doe", dob: Date.new(1985, 3, 15), sex_at_birth: "Male",
          assessments: [
            {
              reference: "REF-2024-001", header_line: 1,
              observations: [
                { code: "8480-6", name: "Blood Pressure (Systolic)", value: 120.0, units: "mmHg", line: 2 },
                { code: "8462-4", name: "Blood Pressure (Diastolic)", value: 80.0, units: "mmHg", line: 3 }
              ]
            }
          ]
        }
      ],
      errors: []
    }

    LabResultPersisterService.call(parsed)
    LabResultPersisterService.call(parsed)

    assert_equal 1, Patient.count
    assert_equal 1, Assessment.count
    assert_equal 2, Assessment.first.observations.count
  end

  test "parse-time errors are present unchanged in the output" do
    parse_errors = [ { line: 5, message: "Unknown observation code: '9999-9'" } ]
    parsed = { patients: [], errors: parse_errors }

    result = LabResultPersisterService.call(parsed)

    assert_equal parse_errors, result[:errors]
  end

  test "a persistence failure for one patient is recorded as an error and does not abort the rest of the batch" do
    parsed = {
      patients: [
        {
          name: "Bad Patient", dob: Date.new(2000, 1, 1), sex_at_birth: "Male",
          assessments: [ { reference: "REF-BAD", header_line: 10, observations: [] } ]
        },
        {
          name: "Good Patient", dob: Date.new(2000, 1, 1), sex_at_birth: "Female",
          assessments: [ { reference: "REF-GOOD", header_line: 20, observations: [] } ]
        }
      ],
      errors: []
    }

    original_create = Patient.method(:create!)
    Patient.stub(:create!, ->(attrs) { attrs[:name] == "Bad Patient" ? raise("boom") : original_create.call(attrs) }) do
      result = LabResultPersisterService.call(parsed)

      assert_equal 1, result[:patients].size
      assert_equal "Good Patient", result[:patients].first[:record].name
      assert_equal 1, Patient.count

      error = result[:errors].find { |e| e[:message].include?("Bad Patient") }
      refute_nil error
      assert_equal 10, error[:line]
    end
  end

  test "newly created assessments have a blank date" do
    parsed = {
      patients: [
        {
          name: "John Doe", dob: Date.new(1985, 3, 15), sex_at_birth: "Male",
          assessments: [ { reference: "REF-2024-001", header_line: 1, observations: [] } ]
        }
      ],
      errors: []
    }

    result = LabResultPersisterService.call(parsed)

    assert_nil result[:patients].first[:assessments].first[:record].date
  end

  test "composes end-to-end with the real parser" do
    parsed = LabResultParserService.call(file_fixture("john_doe_hl7.txt").read)
    result = LabResultPersisterService.call(parsed)

    assert_empty result[:errors]
    assert_equal 1, Patient.count
    assert_equal 1, Assessment.count
    assert_equal 4, Assessment.first.observations.count
  end
end
