class LabResultImport
  include Mongoid::Document
  include Mongoid::Timestamps

  STATUSES = %w[pending processing completed completed_with_errors failed].freeze

  field :filename, type: String
  field :content, type: String
  field :status, type: String, default: "pending"
  # Named `import_errors`, not `errors` — Mongoid raises Mongoid::Errors::InvalidField
  # for `errors` since ActiveModel::Validations already defines that method.
  field :import_errors, type: Array, default: []

  validates :content, presence: true
end
