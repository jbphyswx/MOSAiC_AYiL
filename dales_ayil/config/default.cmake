# Juwels GCC with parastation  - v. 2023
# use with: 
# load modules:
#           
#   module load Stages/2023
#   module load GCC/11.3.0   ParaStationMPI/5.8.0-1
#   module load netCDF-Fortran/4.6.0
#   module load CMake
#   # module load HDF5/1.12.2   # implicitly loaded
#   # module load netCDF/4.9.0  # implicitly loaded
#  
#
set(CMAKE_Fortran_COMPILER "gfortran" ) # "ifort") #"gfortran")
set(Fortran_COMPILER_WRAPPER mpif90 ) # mpiifort)

set(USER_Fortran_FLAGS "-fbacktrace -finit-real=nan -fdefault-real-8  -fno-f2c -ffree-line-length-none -fallow-argument-mismatch")
set(USER_Fortran_FLAGS_RELEASE "-funroll-all-loops -O3 -fallow-argument-mismatch")
set(USER_Fortran_FLAGS_DEBUG "-W -Wall -Wuninitialized -fcheck=all -fbacktrace -O0 -g -fallow-argument-mismatch -ffpe-trap=invalid,zero,overflow")




