require "test_helper"

class LabResultImportTest < ActiveSupport::TestCase
  test "defaults to pending status" do
    import = LabResultImport.new(filename: "x.txt", content: "data")
    assert_equal "pending", import.status
  end

  test "requires content" do
    import = LabResultImport.new(filename: "x.txt", content: "")
    refute import.valid?
    assert_includes import.errors[:content], "can't be blank"
  end
end
