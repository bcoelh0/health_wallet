class LabResultParserService
  OBSERVATION_NAMES_BY_CODE = {
    "8480-6"  => "Blood Pressure (Systolic)",
    "8462-4"  => "Blood Pressure (Diastolic)",
    "8867-4"  => "Heart Rate",
    "8310-5"  => "Body Temperature",
    "9279-1"  => "Respiratory Rate",
    "2708-6"  => "Oxygen Saturation",
    "29463-7" => "Body Weight",
    "8302-2"  => "Body Height",
    "2339-0"  => "Blood Glucose",
    "2093-3"  => "Cholesterol"
  }.freeze

  SEX_CODES = {
    "M" => "Male",
    "F" => "Female"
  }.freeze

  def self.call(input)
    new(input).call
  end

  def initialize(input)
    @content = input.respond_to?(:read) ? input.read.to_s : input.to_s
  end

  def call
    @patients_by_key = {}
    @patients = []
    @errors = []
    @current_assessment = nil

    if @content.strip.empty?
      @errors << { line: nil, message: "File is empty" }
      return { patients: @patients, errors: @errors }
    end

    @content.each_line.with_index(1) do |raw_line, line_number|
      line = raw_line.chomp.chomp("\r")
      next if line.strip.empty?

      fields = line.split("|", -1)

      case fields.size
      when 4
        handle_header(fields, line_number)
      when 3
        handle_observation(fields, line_number)
      else
        @errors << { line: line_number, message: "Malformed line: expected 3 or 4 pipe-delimited fields, got #{fields.size}" }
      end
    end

    { patients: @patients, errors: @errors }
  end

  private

  def handle_header(fields, line_number)
    name, dob_raw, sex_raw, reference = fields.map(&:strip)
    valid = true

    if name.empty?
      @errors << { line: line_number, message: "Patient name is blank" }
      valid = false
    end

    dob = begin
      Date.strptime(dob_raw, "%Y-%m-%d")
    rescue ArgumentError, TypeError
      @errors << { line: line_number, message: "Invalid date of birth: '#{dob_raw}' (expected YYYY-MM-DD)" }
      valid = false
      nil
    end

    sex_at_birth = SEX_CODES[sex_raw.upcase]
    if sex_at_birth.nil?
      @errors << { line: line_number, message: "Invalid sex_at_birth code: '#{sex_raw}' (expected M or F)" }
      valid = false
    end

    if reference.empty?
      @errors << { line: line_number, message: "Assessment reference is blank" }
      valid = false
    end

    unless valid
      @current_assessment = nil
      return
    end

    patient_key = [ name, dob, sex_at_birth ]
    patient = @patients_by_key[patient_key]
    unless patient
      patient = { name: name, dob: dob, sex_at_birth: sex_at_birth, assessments: [] }
      @patients_by_key[patient_key] = patient
      @patients << patient
    end

    @current_assessment = { reference: reference, header_line: line_number, observations: [] }
    patient[:assessments] << @current_assessment
  end

  def handle_observation(fields, line_number)
    code, value_raw, units = fields.map(&:strip)

    if @current_assessment.nil?
      @errors << { line: line_number, message: "Observation line found before any assessment header" }
      return
    end

    name = OBSERVATION_NAMES_BY_CODE[code]
    if name.nil?
      @errors << { line: line_number, message: "Unknown observation code: '#{code}'" }
      return
    end

    value = begin
      Float(value_raw)
    rescue ArgumentError, TypeError
      @errors << { line: line_number, message: "Non-numeric observation value: '#{value_raw}'" }
      nil
    end
    return if value.nil?

    @current_assessment[:observations] << { code: code, name: name, value: value, units: units, line: line_number }
  end
end
