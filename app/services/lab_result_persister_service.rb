class LabResultPersisterService
  def self.call(parsed_data)
    new(parsed_data).call
  end

  def initialize(parsed_data)
    @input_patients = parsed_data[:patients] || []
    @errors = (parsed_data[:errors] || []).dup
  end

  def call
    patients = @input_patients.map { |patient_hash| persist_patient(patient_hash) }.compact
    { patients: patients, errors: @errors }
  end

  private

  def persist_patient(patient_hash)
    patient_record = Patient.where(
      name: patient_hash[:name],
      dob: patient_hash[:dob],
      sex_at_birth: patient_hash[:sex_at_birth]
    ).first
    created = patient_record.nil?
    patient_record ||= Patient.create!(patient_hash.slice(:name, :dob, :sex_at_birth))

    assessments = patient_hash[:assessments].map { |assessment_hash| persist_assessment(patient_record, assessment_hash) }.compact
    { record: patient_record, created: created, assessments: assessments }
  rescue StandardError => e
    add_error(patient_hash[:assessments]&.first&.dig(:header_line), "Failed to persist patient '#{patient_hash[:name]}': #{e.message}")
    nil
  end

  def persist_assessment(patient_record, assessment_hash)
    assessment_record = patient_record.assessments.where(reference: assessment_hash[:reference]).first
    created = assessment_record.nil?
    assessment_record ||= patient_record.assessments.create!(reference: assessment_hash[:reference])

    observations = assessment_hash[:observations].map { |observation_hash| persist_observation(assessment_record, observation_hash) }.compact
    { record: assessment_record, created: created, observations: observations }
  rescue StandardError => e
    add_error(assessment_hash[:header_line], "Failed to persist assessment '#{assessment_hash[:reference]}': #{e.message}")
    nil
  end

  def persist_observation(assessment_record, observation_hash)
    observation_record = assessment_record.observations.where(code: observation_hash[:code]).first
    created = observation_record.nil?

    if observation_record
      observation_record.update!(value: observation_hash[:value], units: observation_hash[:units])
    else
      observation_record = assessment_record.observations.create!(observation_hash.slice(:code, :name, :value, :units))
    end

    { record: observation_record, created: created }
  rescue StandardError => e
    add_error(observation_hash[:line], "Failed to persist observation '#{observation_hash[:code]}': #{e.message}")
    nil
  end

  def add_error(line, message)
    @errors << { line: line, message: message }
  end
end
