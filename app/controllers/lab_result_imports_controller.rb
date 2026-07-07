class LabResultImportsController < ApplicationController
  def index
    @lab_result_imports = LabResultImport.desc(:created_at)
  end

  def new
    @lab_result_import = LabResultImport.new
  end

  def create
    uploaded_file = params[:lab_result_import][:file]

    @lab_result_import = LabResultImport.new(
      filename: uploaded_file.respond_to?(:original_filename) ? uploaded_file.original_filename : nil,
      content: uploaded_file.respond_to?(:read) ? uploaded_file.read.force_encoding(Encoding::UTF_8) : nil
    )

    if @lab_result_import.save
      LabResultImportJob.perform_later(@lab_result_import.id.to_s)
      redirect_to lab_result_import_path(@lab_result_import), notice: "File uploaded — processing started."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @lab_result_import = LabResultImport.find(params[:id])
  end
end
