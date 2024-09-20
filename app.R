# Libraries
library(shiny)
library(shinyjs)
library(oro.nifti)
library(oro.dicom)
library(neurobase)
library(papayaWidget)
library(rmarkdown)
library(knitr)
library(tinytex)
library(shinyFiles)
library(base64enc)
library(qpdf)
library(plotly)

tempDir <- tempdir()

 # User Interface
 ui <- fluidPage(
   useShinyjs(),
   tags$head(
    
    tags$script(src = "https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"),
    tags$script(HTML("
      $(document).ready(function() {
        // Screenshot Function
        window.takeScreenshot = function() {
          var element = document.querySelector('#niftiSliceContainer');
          if (!element) {
            Shiny.setInputValue('screenshotError', 'Element not found');
            return;
          }
          html2canvas(element).then(canvas => {
            canvas.toBlob(function(blob) {
              var reader = new FileReader();
              reader.readAsDataURL(blob); 
              reader.onloadend = function() {
                var base64data = reader.result;
                Shiny.setInputValue('screenshotData', base64data);
              }
            });
          }).catch(function(error) {
            Shiny.setInputValue('screenshotError', error.message);
          });
        }

        // Reset Measurement Function
        window.resetMeasurement = function() {
          $('#niftiSliceContainer .measurement-point').remove();
          $('#measurement-line').empty();
          $('#measurement-text').empty();
        }

        Shiny.addCustomMessageHandler('resetMeasurement', function(message) {
          resetMeasurement();
        });

        var measuring = false;
        var points = [];

        function addMeasurementPoint(x, y) {
          $('<div class=\"measurement-point\"></div>').css({
            'left': x + 'px',
            'top': y + 'px'
          }).appendTo('#niftiSliceContainer');
          points.push({x: x, y: y});
          if (points.length === 2) {
            displayMeasurement();
          }
        }

        function displayMeasurement() {
          var lineSvg = '<svg height=\"100%\" width=\"100%\"><line x1=\"' + points[0].x + '\" y1=\"' + points[0].y + '\" x2=\"' + points[1].x + '\" y2=\"' + points[1].y + '\" class=\"line\" /></svg>';
          $('#measurement-line').html(lineSvg);

          var dx = points[1].x - points[0].x;
          var dy = points[1].y - points[0].y;
          var dist = Math.sqrt(dx * dx + dy * dy);
          var pixdim = $('#niftiSliceContainer').data('pixdim') || 1;
          var dist_cm = dist * pixdim / 10;
          Shiny.setInputValue('distance', dist.toFixed(2));
          Shiny.setInputValue('distance_cm', dist_cm.toFixed(2));
          Shiny.setInputValue('points', points);
          var midpointX = (points[0].x + points[1].x) / 2;
          var midpointY = (points[0].y + points[1].y) / 2;
          $('<div class=\"measurement-result\" style=\"left: ' + midpointX + 'px; top: ' + midpointY + 'px;\">' + dist_cm.toFixed(2) + ' cm</div>').appendTo('#measurement-text');

          points = [];
        }

        $('#startMeasure').on('click', function() {
          measuring = true;
          $('#niftiSliceContainer').css('cursor', 'crosshair');
        });

        $('#stopMeasure').on('click', function() {
          measuring = false;
          $('#niftiSliceContainer').css('cursor', 'default');
        });

        $('#resetMeasure').on('click', function() {
          resetMeasurement();
        });

        $('#niftiSliceContainer').on('click', function(e) {
          if (!measuring) return;

          var containerOffset = $(this).offset();
          var x = e.pageX - containerOffset.left;
          var y = e.pageY - containerOffset.top;
          addMeasurementPoint(x, y);
        });

        $('#togglePassword').on('click', function() {
          var passwordField = $('#reportPassword');
          var type = passwordField.attr('type') === 'password' ? 'text' : 'password';
          passwordField.attr('type', type);
          $(this).toggleClass('fa-eye fa-eye-slash');
        });
      });
    "))
  ),
  titlePanel("NIfTI Image Viewer", windowTitle = "NIfTI Viewer"),
  tags$head(
    tags$script('$(function () { $("[data-toggle=\\"tooltip\\"]").tooltip(); });'),
    tags$script(HTML("
      $(document).on('click', '#zoomIn, #zoomOut, #resetZoom', function() {
        var scale = $('#niftiSliceContainer').data('scale') || 1;
        if (this.id === 'zoomIn') {
          scale *= 1.1;
        } else if (this.id === 'zoomOut') {
          scale *= 0.9;
        } else {
          scale = 1;
        }
        $('#niftiSliceContainer').data('scale', scale).css('transform', 'scale(' + scale + ')');
      });
    "))
  ),
  tags$style(HTML("
    .measurement-point {
      position: absolute;
      width: 10px;
      height: 10px;
      background-color: red;
      border-radius: 50%;
      transform: translate(-50%, -50%);
      z-index: 100;
    }
    #measurement-line, #measurement-text {
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      pointer-events: none;
    }
    .line {
      stroke: red;
      stroke-width: 2px;
    }
    .measurement-result {
      position: absolute;
      color: yellow;
      font-size: 16px;
      font-weight: bold;
      z-index: 101;
    }
    #niftiSliceContainer {
      position: relative;
      width: 100%;
      height: auto;
      overflow: hidden;
      transform-origin: top left;
    }
    @media (min-width: 600px) {
      .sidebarPanel {
        width: 100%;
      }
      .mainPanel {
        width: 100%;
      }
    }
    .password-container {
      position: relative;
    }
    .toggle-password {
      position: absolute;
      right: 10px;
      top: 50%;
      transform: translateY(-50%);
      cursor: pointer;
    }
    .password-hint {
      font-size: 12px;
      color: red;
    }
    #papaya-container {
      width: 100%;
      height: 85vh;
      margin: 0;
      padding: 0;
      overflow: hidden;
    }
    #papaya-viewer {
      width: 100%;
      height: 100%;
    }
  ")),
  sidebarLayout(
    sidebarPanel(
      div(class = "top-buttons",
          actionButton("triggerDownload", "Download PDF Report"),
          actionButton("endSession", "End Session and Clear Data")
      ),
      # Conditional Panels for User Options
      conditionalPanel(
        condition = "output.showPasswordField",
        div(class = "password-container",
            passwordInput("reportPassword", "Report Password", value = "", placeholder = "Enter password for PDF report"),
            icon("eye-slash", id = "togglePassword", class = "toggle-password", `aria-hidden` = "true")
        ),
        uiOutput("passwordHint"),
        downloadButton("downloadReport", "Confirm Password")
      ),
      radioButtons('uploadChoice', 'Upload Type',
                   choices = list('DICOM (ZIP)' = 'dicom', 'NIfTI' = 'nifti', 'Example NIfTI' = 'example'), selected = 'example'),
      conditionalPanel(
        condition = "input.uploadChoice == 'dicom'",
        fileInput('dicomZip', 'Choose ZIP File')
      ),
      conditionalPanel(
        condition = "input.uploadChoice == 'nifti'",
        fileInput('file1', 'Choose NIfTI File'),
        fileInput('file2', 'Choose NIfTI File 2')
      ),
      conditionalPanel(
        condition = "input.uploadChoice == 'example'",
        p("Using example NIfTI files: example1.nii and example2.nii")
      ),
      actionButton("startMeasure", "Start Measuring", icon("arrows-alt"), `data-toggle` = "tooltip", title = "Click to start measuring"),
      actionButton("stopMeasure", "Stop Measuring", icon("stop")),
      actionButton("resetMeasure", "Reset Measurement"),
      actionButton("takeScreenshot", "Take Screenshot", onclick = "window.takeScreenshot()"),
      tabsetPanel(id = "tabPanel",
                  type = "tabs",
                  tabPanel("sliceView", "", 
                           radioButtons("sliceViewMode", "",
                                        choices = list("Single" = "single", "All slices" = "all", "Orthographic" = "ortho")),
                           sliderInput('slice', 'Slice Number', min = 1, max = 1, value = 1, step = 1),
                           checkboxInput("moreContrast", "More contrast", value = FALSE)
                  ),
                  tabPanel("overlay", "", 
                           sliderInput('overlaySlice', 'Overlay Slice Number', min = 1, max = 1, value = 1, step = 1)
                  ),
                  tabPanel("Papaya Viewer", "",     
                           uiOutput("papayaCheckbox")
                  ),
                  tabPanel("NIfTI Info", 
                           uiOutput("niftiInfo"),
                           plotOutput("complexPlot")
                  ),
                  tabPanel("General Info", 
                           h2("General Information"),
                           p("THIS PRODUCT IS NOT FOR CLINICAL USE."),
                           p("This software is available for use, as is, free of charge. The software und data derived from this software may not be used for clinical purposes."),
                           p("The authors of this software make no representations or warranties about the suitability of the software, either express or implied, including but not limited to the implied warranties of merchantability, fitness for a particular purpose, non-infringement, or conformance to a specification or standard. The authors of this software shall not be liable for any damages suffered by licensee as a result of using or modifying this software or its derivatives."),
                           p("By using this software, you agree to be bounded by the terms of this license. If you do not agree to the terms of this license, do not use this software.")
                  ),
                  tabPanel("Statistik", 
                           h2("   ")
                  )
      ),
      actionButton("zoomIn", "Zoom In"),
      actionButton("zoomOut", "Zoom Out"),
      actionButton("resetZoom", "Reset Zoom")
    ),
    mainPanel(
      uiOutput("statusMessageUI"),
      div(id = "loading", class = "loading-container", style = "display:none;",
          h3("Loading..."),
          p("Please wait while the images are being processed.")
      ),
      uiOutput("papayaViewerUI"),
      textOutput("statusMessage"),
      div(id = "niftiSliceContainer", style = "position: relative; width: 100%; height: 85vh; overflow: hidden; transform-origin: top left;",
          div(id = "measurement-line"),
          div(id = "measurement-text"),
          imageOutput("niftiSlice", width = "100%", height = "100%")  # Use plotlyOutput instead of imageOutput
      ),
      conditionalPanel(
        condition = "input.tabPanel == 'Statistik'",
        h2("Statistical Analysis"),
        plotOutput("histogramPlot"),
        plotOutput("boxplotPlot"),
        plotOutput("meanIntensityPlot"),
        plotOutput("varianceIntensityPlot"),
        plotlyOutput("scatterPlot3D"),
        plotOutput("correlationMatrix"),
        verbatimTextOutput("descriptive_stats"),
        verbatimTextOutput("descriptive_stats_non_zero")
      )
    )
  )
)

#---- Server Function----
server <- function(input, output, session) {
  
  graphics.off()
  filePaths <- new.env()
  options(shiny.maxRequestSize = 10*1024^2)
  
  #---- Reactive Values----
  reportReady <- reactiveVal(FALSE)
  showPasswordField <- reactiveVal(FALSE)
  statusMessage <- reactiveVal("Welcome! Please upload a file to get started.")
  distanceCM <- reactiveVal(NULL)
  points <- reactiveVal(NULL)
  dimMismatch <- reactiveVal(FALSE)
  
  #---- Function to Validate Uploaded Files----
  validateUpload <- function(file) {
    if (is.null(file)) {
      return(NULL)
    }
    
    # Determine the new file path and name
    if (grepl("\\.nii\\.gz$", file$name)) {
      # If the file is already .nii.gz, no need to rename
      new_file_path <- file$datapath
      new_name <- file$name
    } else if (grepl("\\.gz$", file$name) && !grepl("\\.nii\\.gz$", file$name)) {
      # Rename .gz files to .nii.gz only if they don't already end in .nii.gz
      new_file_path <- sub("\\.gz$", ".nii.gz", file$datapath)
      if (file.exists(file$datapath)) {
        file.rename(file$datapath, new_file_path)
      }
      new_name <- sub("\\.gz$", ".nii.gz", file$name)
    } else {
      new_file_path <- file$datapath
      new_name <- file$name
    }
    
    # Extract the extension from the new file name
    new_ext <- tools::file_ext(new_name)
    
    # Ensure we handle both possible extensions for .nii.gz
    if (grepl("\\.nii\\.gz$", new_name)) {
      new_ext <- "nii.gz"
    }
    
    if (!new_ext %in% c("nii", "nii.gz", "zip")) {
      stop("Invalid file type. Please upload a NIfTI or DICOM file.")
    }
    
    # Update file's datapath to the new file path
    file$datapath <- new_file_path
    
    return(file)
  }
  
  #---- Function to Remove Files----
  removeFiles <- function() {
    if (!is.null(filePaths$file1) && file.exists(filePaths$file1)) {
      file.remove(filePaths$file1)
    }
    if (!is.null(filePaths$file2) && file.exists(filePaths$file2)) {
      file.remove(filePaths$file2)
    }
    if (!is.null(filePaths$dicomZip) && file.exists(filePaths$dicomZip)) {
      file.remove(filePaths$dicomZip)
    }
    if (!is.null(filePaths$reportDir) && dir.exists(filePaths$reportDir)) {
      unlink(filePaths$reportDir, recursive = TRUE)
    }
    
    additional_dirs <- list(
      "nii_images", 
      "temp_dir",  
      "screenshots" 
    )
    
    for (dir_name in additional_dirs) {
      dir_path <- file.path(tempdir(), dir_name)
      if (dir.exists(dir_path)) {
        unlink(dir_path, recursive = TRUE)
      }
    }
    unlink(tempDir, recursive = TRUE)
  }
  
  #---- Function to Convert DICOM to NIfTI----
  convertDicomToNifti <- function(dicomDir) {
    dicomFiles <- list.files(dicomDir, pattern = "\\.dcm$", full.names = TRUE)
    if (length(dicomFiles) == 0) {
      statusMessage("No DICOM files found in the selected directory.")
      return(NULL)
    }
    
    dicomData <- lapply(dicomFiles, function(file) {
      tryCatch({
        dicom <- oro.dicom::readDICOMFile(file)
        return(list(hdr = dicom$hdr, img = dicom$img))
      }, error = function(e) {
        return(NULL)
      })
    })
    
    dicomData <- Filter(Negate(is.null), dicomData)
    if (length(dicomData) == 0) {
      statusMessage("No valid DICOM files could be read.")
      return(NULL)
    }
    
    hdr_list <- lapply(dicomData, function(x) x$hdr)
    img_list <- lapply(dicomData, function(x) x$img)
    
    combined_data <- list(hdr = hdr_list, img = img_list)
    
    tryCatch({
      niftiImage <- oro.dicom::dicom2nifti(combined_data)
      if (is.null(niftiImage)) {
        stop("Failed to convert DICOM files to NIfTI format.")
      }
      statusMessage("DICOM files converted and NIfTI image loaded successfully.")
      return(niftiImage)
    }, error = function(e) {
      statusMessage("Failed to convert DICOM files to NIfTI format.")
      return(NULL)
    })
  }
  
  #---- Reactive Functions to Handle NIfTI Data Loading and Processing----
  niftiData1 <- reactive({
    if (input$uploadChoice == 'dicom') {
      req(input$dicomZip)
      unzip_folder <- unzip(input$dicomZip$datapath, exdir = tempdir())
      dicomDir <- dirname(unzip_folder[1])
      if (dir.exists(dicomDir)) {
        niftiImage <- convertDicomToNifti(dicomDir)
        runjs(sprintf("$('#niftiSliceContainer').data('pixdim', %f);", 
                      niftiImage@pixdim[2]))
        return(niftiImage)
      }
    } else if (input$uploadChoice == 'nifti') {
      req(input$file1)
      new_file_path <- sub("\\.gz$", ".nii.gz", input$file1$datapath)
      if (file.exists(input$file1$datapath)) {
        file.rename(input$file1$datapath, new_file_path)
      }
      niftiImage <- oro.nifti::readNIfTI(new_file_path, reorient = FALSE)
      runjs(sprintf("$('#niftiSliceContainer').data('pixdim', %f);",
                    niftiImage@pixdim[2]))
      return(niftiImage)
    } else if (input$uploadChoice == 'example') {
      example1_path <- file.path(getwd(), "example1.nii")
      niftiImage <- oro.nifti::readNIfTI(example1_path, reorient = FALSE)
      runjs(sprintf("$('#niftiSliceContainer').data('pixdim', %f);", 
                    niftiImage@pixdim[2]))
      return(niftiImage)
    }
  })
  
  niftiData2 <- reactive({
    if (input$uploadChoice == 'nifti') {
      req(input$file2)
      new_file_path2 <- sub("\\.gz$", ".nii.gz", input$file2$datapath)
      if (file.exists(input$file2$datapath)) {
        file.rename(input$file2$datapath, new_file_path2)
      }
      niftiImage2 <- oro.nifti::readNIfTI(new_file_path2, reorient = FALSE)
      return(niftiImage2)
    } else if (input$uploadChoice == 'example') {
      example2_path <- file.path(getwd(), "example2.nii")
      niftiImage2 <- oro.nifti::readNIfTI(example2_path, reorient = FALSE)
      return(niftiImage2)
    }
  })
  
  #---- Adjust Contrast of NIfTI Image----
  adjust_contrast <- function(nii, more_contrast = FALSE) {
    if (more_contrast) {
      return(robust_window(nii, probs = c(0.0, 0.99)))
    }
    return(nii)
  }
  
  #---- Process Image overlay----
  process_image_display <- function(nii1, input, sliceNum = 1) {
    if (input$tabPanel == "overlay") {
      if (is.null(niftiData2())) {
        statusMessage("Both files are required for overlay.")
        return(NULL)
      }
      req(dimMismatch() == FALSE)
      nii2 <- niftiData2()
      if (is.null(nii2)) {
        statusMessage("Failed to load the second NIfTI file for overlay.")
        return(NULL)
      }
      sliceNum <- input$overlaySlice
      overlay(nii1, nii2, z = sliceNum, plot.type = "single")
    } else {
      render_slice_view(nii1, input)
    }
  }
  
  #---- Render Slice View----
  render_slice_view <- function(nii1, input) {
    sliceNum <- input$slice
    if (input$sliceViewMode == "single") {
      image(nii1[,,sliceNum], col = gray.colors(256), xaxt = 'n', yaxt = 'n', 
            xlab = '', ylab = '', asp = 1)
      if (!is.null(points())) {
        pt <- points()
        if (length(pt) == 2) {
          segments(pt[[1]]$x, pt[[1]]$y, pt[[2]]$x, pt[[2]]$y, col = "red", lwd = 2)
          points(pt[[1]]$x, pt[[1]]$y, col = "red", pch = 19, cex = 1.5)
          points(pt[[2]]$x, pt[[2]]$y, col = "red", pch = 19, cex = 1.5)
          text(mean(c(pt[[1]]$x, pt[[2]]$x)), mean(c(pt[[1]]$y, pt[[2]]$y)), 
               labels = paste0(distanceCM(), " cm"), col = "yellow", cex = 1.5)
        }
      }
    } else if (input$sliceViewMode == "all") {
      render_all_slices(nii1)
    } else if (input$sliceViewMode == "ortho") {
      if (!is.null(input$file2) || !dimMismatch() || !is.null(niftiData2())) {
        nii2 <- niftiData2()
        if (is.null(nii2)) {
          statusMessage("Failed to load the second NIfTI file for orthographic view.")
          return(NULL)
        }
        neurobase::double_ortho(nii1, nii2)
      } else {
        if (input$moreContrast) {
          oro.nifti::orthographic(nii1, y = nii1 > 300)
        } else {
          oro.nifti::orthographic(nii1)
        }
      }
    }
  }
  
  #---- Render All Slices----
  render_all_slices <- function(nii) {
    numSlices <- dim(nii)[3]
    par(mfrow = c(ceiling(sqrt(numSlices)), ceiling(sqrt(numSlices))), mar = c(1, 1, 1, 1))
    for (sliceNum in 1:numSlices) {
      img <- nii[,,sliceNum]
      if (!is.matrix(img)) img <- as.matrix(img)
      image(1:dim(img)[1], 1:dim(img)[2], z = t(img[nrow(img):1, ]), col = gray.colors(256),
            xaxt = 'n', yaxt = 'n', xlab = '', ylab = '')
    }
  }
  
  #---- Create Image Output----
  create_image_output <- function(input) {
    req(niftiData1())
    nii1 <- niftiData1()
    nii1 <- adjust_contrast(nii1, input$moreContrast)
    
    tmpfile <- tempfile(fileext = '.png')
    png(tmpfile, width = 800, height = 800)
    par(mar = c(0, 0, 0, 0))
    
    process_image_display(nii1, input)
    
    dev.off()
    return(list(src = tmpfile, contentType = 'image/png'))
  }
  
  #---- Create Custom Plot----
  create_custom_plot <- function(nii1, nii2 = NULL) {
    par(mfrow = c(1, if (!is.null(nii2)) 2 else 1))
    if (!is.null(nii1)) {
      filtered_data1 <- nii1[nii1 != 0]
      if (length(filtered_data1) > 0) {
        plot(density(filtered_data1), main = "File 1 non-zero Density Plot ")
      } else {
        plot(1, type = 'n', axes = FALSE, xlab = '', ylab = '', main = 'No non-zero data for File 1')
        text(1, 0.5, "All data is zero or empty")
      }
    }
    if (!is.null(nii2)) {
      filtered_data2 <- nii2[nii2 != 0]
      if (length(filtered_data2) > 0) {
        plot(density(filtered_data2), main = "File 2 non-zero Density Plot")
      } else {
        plot(1, type = 'n', axes = FALSE, xlab = '', ylab = '', main = 'No non-zero data for File 2')
        text(1, 0.5, "All data is zero or empty")
      }
    }
    par(mfrow = c(1, 1))
  }
  #---- Create density Plot----
  save_density_plot <- function(data, filename, plot_title) {
    if (length(data[data != 0]) > 0) {
      png(filename)
      plot(density(data[data != 0]), main = plot_title)
      dev.off()
    } else {
      png(filename)
      plot(1, type = 'n', axes = FALSE, xlab = '', ylab = '', main = plot_title)
      text(1, 0.5, "All data is zero or empty")
      dev.off()
    }
  }
  
  #---- Create report----
  reportRe <- function() {
    statusMessage("Please wait while the report is being prepared...")
    reportReady(FALSE)
    
    nii1 <- req(niftiData1())
    nii2 <- if (!is.null(input$file2)) niftiData2() else NULL
    
    dir_name <- paste0(tempDir, "/nii_images")
    if (!dir.exists(dir_name)) {
      dir.create(dir_name)
      statusMessage(paste("Created directory:", dir_name))
    } else {
      statusMessage(paste("Directory already exists:", dir_name))
    }
    
    save_density_plot(nii1[nii1 != 0], paste0(dir_name, "/file1_density.png"),
                      "File 1 Density Plot")
    if (!is.null(nii2)) {
      save_density_plot(nii2[nii2 != 0], paste0(dir_name, "/file2_density.png"),
                        "File 2 Density Plot")
    }
    
    num_slices <- if (!is.null(nii2)) min(dim(nii1)[3], dim(nii2)[3]) else dim(nii1)[3]
    
    for (i in 1:num_slices) {
      slice1_path <- sprintf("%s/slice1_%03d.png", dir_name, i)
      png(slice1_path, width = 800, height = 800)
      par(mar = c(0, 0, 0, 0))
      image(nii1[,,i], col = gray.colors(256), axes = FALSE, xlab = '', ylab = '')
      dev.off()
      
      if (!is.null(nii2)) {
        slice2_path <- sprintf("%s/slice2_%03d.png", dir_name, i)
        overlay_path <- sprintf("%s/overlay_%03d.png", dir_name, i)
        
        png(slice2_path, width = 800, height = 800)
        par(mar = c(0, 0, 0, 0))
        image(nii2[,,i], col = gray.colors(256), axes = FALSE, xlab = '', ylab = '')
        dev.off()
        
        png(overlay_path, width = 800, height = 800)
        par(mar = c(0, 0, 0, 0))
        overlay(nii1, nii2, z = i, plot.type = "single")
        dev.off()
      }
    }
    
    if (!is.null(nii2)) {
      ortho_path <- sprintf("%s/ortho_view.png", dir_name)
      png(ortho_path, width = 800, height = 800)
      par(mar = c(0, 0, 0, 0))
      neurobase::double_ortho(nii1, nii2)
      dev.off()
    } else {
      ortho_path <- sprintf("%s/ortho_view.png", dir_name)
      png(ortho_path, width = 800, height = 800)
      par(mar = c(0, 0, 0, 0))
      oro.nifti::orthographic(nii1)
      dev.off()
    }
    
    screenshot_path <- file.path(dir_name, "plot_with_measurement.png")
    
    reportReady(TRUE)
    statusMessage("Report ready.")
  }
  
  #---- Create nifti info----
  extract_nifti_info <- function(nii) {
    if (is.null(nii)) {
      return("No NIfTI data available.")
    }
    
    info <- sprintf(
      "NIfTI-1 format\nType: %s\nData Type: %s\nBits per Pixel: %s\nDimension: 
      %s\nPixel Dimension: %s mm\nVoxel Units: mm\nTime Units: sec\n",
      class(nii),
      nii@datatype,
      nii@bitpix,
      paste(dim(nii), collapse = ' x '),
      paste(round(nii@pixdim, 2), collapse = ' x ')
    )
    
    return(info)
  }
  
  #---- Observe----
  observeEvent(input$distance_cm, {
    dist_cm <- as.numeric(input$distance_cm)
    distanceCM(dist_cm)
    statusMessage(paste("Measured distance:", dist_cm, "cm"))
  })
  
  observeEvent(input$points, {
    points(input$points)
  })
  
  observe({
    if (input$tabPanel == "Papaya Viewer" || input$tabPanel == "Statistik") {
      shinyjs::hide("niftiSliceContainer")
      
      if (!is.null("file1")){
        shinyjs::hide("statusMessage")
      }
    } else {
      shinyjs::show("niftiSliceContainer")
      shinyjs::show("statusMessage")
    }
  })
  
  observe({
    nii1 <- niftiData1()
    if (!is.null(nii1)) {
      updateSliderInput(session, 'slice', max = dim(nii1)[3])
    }
    nii2 <- niftiData2()
    if (!is.null(nii2)) {
      updateSliderInput(session, 'overlaySlice', max = dim(nii2)[3])
    }
  })
  
  observe({
    if (!is.null(niftiData1()) && !is.null(niftiData2())) {
      dimMismatch(!all(dim(niftiData1()) == dim(niftiData2())))
    }
  })
  
  observe({
    if (dimMismatch()) {
      statusMessage("The dimensions of the uploaded files do not match. Please upload compatible files.")
    }
  })
  
  observe({
    if (input$tabPanel == "overlay") {
      if (is.null(niftiData1()) || is.null(niftiData2())) {
        statusMessage("Both files are required for overlay.")
      } else {
        statusMessage("Overlay view is available.")
      }
    }
  })
  
  observeEvent(input$tabPanel, {
    session$sendCustomMessage(type = 'resetMeasurement', message = list())
  })
  
  observeEvent(input$sliceViewMode, {
    session$sendCustomMessage(type = 'resetMeasurement', message = list())
  })
  observeEvent(input$triggerDownload, {
    showPasswordField(TRUE)
  })
  
  observeEvent(input$confirmPassword, {
    if (nzchar(input$reportPassword)) {
      shinyjs::click("downloadReport")
    }
  })
  
  observeEvent(input$dicomZip, {
    req(input$dicomZip)
    filePaths$dicomZip <- input$dicomZip$datapath
  })
  
  observe({
    filePaths$reportDir <- paste0(tempdir(), "/nii_images")
  })
  
  observeEvent(input$endSession, {
    removeFiles()
    statusMessage("Session ended. All data cleared.")
    stopApp()
  })
  
  session$onSessionEnded(function() {
    removeFiles()
  })
  
  observeEvent(input$screenshotData, {
    req(input$screenshotData)
    dir_name <- paste0(tempdir(), "/nii_images")
    if (!dir.exists(dir_name)) {
      dir.create(dir_name)
      statusMessage(paste("Created directory for screenshot:", dir_name))
    }
    
    base64_str <- gsub("^data:image/png;base64,", "", input$screenshotData)
    png_file <- file.path(dir_name, "screenshot.png")
    
    png_data <- base64enc::base64decode(base64_str)
    writeBin(png_data, png_file)
    
    statusMessage(paste("Screenshot saved to:", png_file))
  })
  
  observeEvent(input$screenshotError, {
    statusMessage(paste("Screenshot error:", input$screenshotError))
  })
  
  observeEvent(input$uploadChoice, {
    statusMessage("Welcome! Please upload a file to get started.")
    
    shinyjs::reset("niftiSliceContainer")
    shinyjs::reset("niftiSlice")
    
    shinyjs::runjs("resetMeasurement();")
  })
  
  observeEvent(input$file1, {
    req(validateUpload(input$file1))
    filePaths$file1 <- input$file1$datapath
    statusMessage("File 1 uploaded successfully.")
  })
  
  observeEvent(input$file2, {
    req(validateUpload(input$file2))
    filePaths$file2 <- input$file2$datapath
    statusMessage("File 2 uploaded successfully.")
  })
  
  observe({
    password <- input$reportPassword
    hint <- if (nchar(password) < 8 || !grepl("[A-Z]", password) || !grepl("[a-z]", password) || !grepl("[0-9]", password) || !grepl("[!@#$%^&*]", password)) {
      "Password must be at least 8 characters long, and include an uppercase letter, a lowercase letter, a number, and a special character."
    } else {
      ""
    }
    output$passwordHint <- renderUI({
      if (hint != "") {
        div(class = "password-hint", hint)
      } else {
        NULL
      }
    })
  })
  
  #---- Output----
  output$niftiInfo <- renderUI({
    nii1 <- niftiData1()
    if (!is.null(nii1)) {
      info <- list(
        HTML("NIfTI-1 format<br>"),
        HTML("Type: ", class(nii1), "<br>"),
        HTML(paste("Data Type: ", nii1@datatype, "<br>")),
        HTML(paste("Bits per Pixel: ", nii1@bitpix, "<br>")),
        HTML(paste("Dimension: ", paste(dim(nii1), collapse = ' x '), "<br>")),
        HTML(paste("Pixel Dimension: ", paste(round(nii1@pixdim, 2), collapse = ' x '), "<br>"))
      )
      do.call(tagList, info)
    }
  })
  
  output$niftiSlice <- renderImage({
    create_image_output(input)
  }, deleteFile = TRUE)
  
  output$papayaViewerUI <- renderUI({
    req(input$tabPanel)
    if (input$tabPanel == "Papaya Viewer") {
      validate(need(!is.null(niftiData1()), 'Please upload a NIfTI or DICOM file.'))
      nii1 <- niftiData1()
      papaya(img = nii1, sync_view = TRUE, hide_toolbar = TRUE, 
             hide_controls = TRUE, orthogonal = TRUE)
    }
  })
  
  output$complexPlot <- renderPlot({
    req(input$file1)
    nii1 <- niftiData1()
    nii2 <- if (!is.null(input$file2)) niftiData2()
    create_custom_plot(nii1, nii2)
  })
  
  output$histogramPlot <- renderPlot({
    req(niftiData1())
    nii1 <- niftiData1()
    if (input$tabPanel == "Statistik") {
      plot(density(nii1), main = "Density Plot of NIfTI Data", xlab = "Intensity", ylab = "Density")
    }
  })
  
  output$histogramPlotNonZero <- renderPlot({
    req(niftiData1())
    nii1 <- niftiData1()
    non_zero_values <- nii1[nii1 != 0]
    if (input$tabPanel == "Statistik") {
      plot(density(non_zero_values), main = "Density Plot of Non-Zero NIfTI Data", xlab = "Intensity", ylab = "Density")
    }
  })
  
  output$descriptive_stats <- renderPrint({
    req(niftiData1())
    nii1 <- niftiData1()
    stats <- summary(nii1)
    sd_val <- sd(nii1)
    if (input$tabPanel == "Statistik") {
      formatted_stats <- paste(
        "Minimum:", stats[1], "\n",
        "1st Qu.:", stats[2], "\n",
        "Median:", stats[3], "\n",
        "Mean:", stats[4], "\n",
        "3rd Qu.:", stats[5], "\n",
        "Maximum:", stats[6], "\n",
        "Standard Deviation:", sd_val
      )
      
      cat(formatted_stats)
    }
  })
  
  output$descriptive_stats_non_zero <- renderPrint({
    req(niftiData1())
    nii1 <- niftiData1()
    non_zero_values <- nii1[nii1 != 0]
    stats <- summary(non_zero_values)
    sd_val <- sd(non_zero_values)
    if (input$tabPanel == "Statistik") {
      formatted_stats <- paste(
        "Minimum:", stats[1], "\n",
        "1st Qu.:", stats[2], "\n",
        "Median:", stats[3], "\n",
        "Mean:", stats[4], "\n",
        "3rd Qu.:", stats[5], "\n",
        "Maximum:", stats[6], "\n",
        "Standard Deviation:", sd_val
      )
      
      cat(formatted_stats)
    }
  })
  
  output$boxplotPlot <- renderPlot({
    req(niftiData1())
    nii1 <- niftiData1()
    boxplot(nii1[nii1 != 0], main = "Boxplot of Intensity Values", ylab = "Intensity", col = "green")
  })
  
  output$meanIntensityPlot <- renderPlot({
    req(niftiData1())
    nii1 <- niftiData1()
    mean_intensities <- apply(nii1, 3, function(slice) mean(slice[slice != 0]))
    plot(mean_intensities, type = 'o', main = "Mean Intensity per Slice", xlab = "Slice", ylab = "Mean Intensity", col = "purple")
  })
  
  output$varianceIntensityPlot <- renderPlot({
    req(niftiData1())
    nii1 <- niftiData1()
    variance_intensities <- apply(nii1, 3, function(slice) var(slice[slice != 0]))
    plot(variance_intensities, type = 'o', main = "Variance of Intensity per Slice", xlab = "Slice", ylab = "Variance", col = "red")
  })
  
  output$showPasswordField <- reactive({
    showPasswordField()
  })
  
  outputOptions(output, 'showPasswordField', suspendWhenHidden = FALSE)
  
  
  output$statusMessage <- renderText({
    statusMessage()
  })
  
  output$downloadReport <- downloadHandler(
    filename = function() {
      paste0("nifti-report-", Sys.Date(), ".pdf")
    },
    
    content = function(file) {
      statusMessage("Report is being prepared... Please wait.")
      reportRe()
      req(reportReady())
      
      reportDir <- tempDir
      tempReport <- file.path(reportDir, "nifti-report.Rmd")
      
      imgDir <- paste0(reportDir, "/nii_images/")
      all_files <- list.files(imgDir, pattern = "\\.png$", full.names = TRUE)
      
      if (length(all_files) == 0) {
        stop("No images to copy.")
      }
      
      file.copy(all_files, reportDir, overwrite = TRUE)
      image_files <- list.files(reportDir, pattern = "\\.png$", full.names = FALSE)
      image_files <- sort(image_files)
      imgMarkdown <- ""
      
      for (img in image_files) {
        captionText <- sub("\\.png$", "", img)
        imgMarkdown <- paste(imgMarkdown, sprintf("![%s](%s)\n\n*%s*\n\n",
                                                  captionText, img, captionText), sep = "")
      }
      
      niftiInfo <- extract_nifti_info(niftiData1())
      dist_cm <- distanceCM()
      measurementText <- ""
      if (!is.null(dist_cm)) {
        measurementText <- sprintf("Measured distance: %.2f cm\n\n", dist_cm)
      }
      
      screenshot_path <- file.path(reportDir, "plot_with_measurement.png")
      screenshotMarkdown <- if (file.exists(screenshot_path)) {
        sprintf("![Measurement Plot](plot_with_measurement.png)\n\n*Measurement Plot*\n\n")
      } else {
        ""
      }
      
      reportContent <- sprintf(
        "---\ntitle: 'NIfTI Image Report'\noutput: pdf_document\n---\n\n# NIfTI Image Report\n\n## NIfTI Information\n\n%s\n\n%s%s## Images\n\n%s",
        niftiInfo, measurementText, screenshotMarkdown, imgMarkdown
      )
      
      writeLines(reportContent, tempReport)
      rmarkdown::render(tempReport, output_file = file.path(reportDir, "nifti-report.pdf"))
      
      # Encrypt the PDF with the user-provided password
      password <- input$reportPassword
      pdf_file <- file.path(reportDir, "nifti-report.pdf")
      if (nzchar(password)) {
        encrypted_pdf_file <- file.path(reportDir, "nifti-report-encrypted.pdf")
        qpdf_path <- try(system("which qpdf", intern = TRUE), silent = TRUE)
        
        if (!inherits(qpdf_path, "try-error") && nzchar(qpdf_path)) {
          encrypt_command <- paste("qpdf --encrypt", password, password, "256 --", pdf_file, encrypted_pdf_file)
          system(encrypt_command)
          file.rename(encrypted_pdf_file, file)
          statusMessage("Report created and encrypted successfully.")
        } else {
          file.rename(pdf_file, file)
          warning("qpdf not found or failed to run, skipping encryption.")
          statusMessage("Report created without encryption.")
        }
      } else {
        file.rename(pdf_file, file)
        statusMessage("Report created without encryption.")
      }
      
      reportReady(TRUE)
      statusMessage("The report is now ready for download.")
      showPasswordField(FALSE)
      # Reset the password field
      updateTextInput(session, "reportPassword", value = "")
    }
  )
  
  
  
  
  
}

graphics.off()
shinyApp(ui, server)
