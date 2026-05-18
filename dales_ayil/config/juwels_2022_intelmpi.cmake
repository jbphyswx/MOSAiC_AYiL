# Juwels GCC with parastation  - v. 2022
# use with: 
# load modules:
# module load Intel/2021.4.0 IntelMPI/2021.4.0
# module load netCDF-Fortran/4.5.3
# module load HDF
# module load netCDF
# module load CMake 
#
#
set(CMAKE_Fortran_COMPILER "ifort") #"gfortran")
set(Fortran_COMPILER_WRAPPER mpiifort)

set(USER_Fortran_FLAGS "-fbacktrace -finit-real=nan -fdefault-real-8  -traceback  -ffree-line-length-none -fallow-argument-mismatch")
set(USER_Fortran_FLAGS_RELEASE "-funroll-all-loops -O3 -traceback -fallow-argument-mismatch")
set(USER_Fortran_FLAGS_DEBUG "-W -Wall -Wuninitialized -traceback -fcheck=all -fbacktrace -O0 -g -fallow-argument-mismatch -ffpe-trap=invalid,zero,overflow")


set(NETCDF_INCLUDE_DIR "/gpfs/software/juwels/stages/2022/software/netCDF-Fortran/4.5.3-iimpi-2021b/include/")
set(NETCDF_LIB_1      "/gpfs/software/juwels/stages/2022/software/netCDF/4.8.1-iimpi-2021b/lib64/libnetcdf.so")
set(NETCDF_LIB_2      "/gpfs/software/juwels/stages/2022/software/netCDF-Fortran/4.5.3-iimpi-2021b/lib64/libnetcdff.so")
set(HDF5_LIB_1        "/gpfs/software/juwels/stages/2022/software/HDF5/1.12.1-iimpi-2021b/lib64/libhdf5.so")
set(HDF5_LIB_2        "/gpfs/software/juwels/stages/2022/software/HDF5/1.12.1-iimpi-2021b/lib64/libhdf5_fortran.so") # "/gpfs/software/juwels/stages/2022/software/HDF/4.2.15-GCCcore-11.2.0/lib64/libmfhdf.so")

set(SZIP_LIB           "") #   "/opt/rrzk/lib/szip/szip-2.1/lib/libsz.so")
set(LIBS ${NETCDF_LIB_1} ${NETCDF_LIB_2}  ${HDF5_LIB_1} ${HDF5_LIB_2} ${SZIP_LIB} m z curl)



