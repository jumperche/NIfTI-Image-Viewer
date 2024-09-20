# NIfTI Image Viewer

**Version:** 1.0.0  
**Author:** Rosalina Gramatikov  
**License:** BSD 3-Clause

## Overview

The **NIfTI Image Viewer** is an interactive Shiny application designed for viewing and analyzing medical imaging data in the NIfTI format. 
This application allows users to upload NIfTI and DICOM files, offers various viewing modes, and provides basic statistical analyses.

## Demo app
https://jumperche.shinyapps.io/MRI-Viewer/

## Features

- **Supported Formats:**
  - NIfTI files (`.nii`, `.nii.gz`)
  - DICOM files (packed as `.zip`)
  
- **Viewing Options:**
  - Single slice view
  - View all slices
  - Orthographic view
  - Overlay of two images
  - Integration with Papaya Viewer
  
- **Tools:**
  - Measurement tool for distance measurement within images
  - Zoom functions (zoom in, zoom out, reset zoom)
  - Screenshot functionality
  
- **Report Generation:**
  - Generate a PDF report of the analysis with password protection
  
- **Statistical Analyses:**
  - Histograms
  - Boxplots
  - Mean and variance per slice
  - 3D scatter plots
  - Correlation matrix
  - Descriptive statistics (including non-zero values)

## Nifti data
https://github.com/muschellij2/Neurohacking_data/archive/v0.0.zip

### Prerequisites

- **R** (version 3.6 or higher)
- **RStudio** (recommended for ease of use)
- **Git** (optional, for version control)

### Required R Packages

Install the necessary R packages using the following command:

```R
install.packages(c(
  "shiny",
  "shinyjs",
  "oro.nifti",
  "oro.dicom",
  "neurobase",
  "papayaWidget",
  "rmarkdown",
  "knitr",
  "tinytex",
  "shinyFiles",
  "base64enc",
  "qpdf",
  "plotly"
))
