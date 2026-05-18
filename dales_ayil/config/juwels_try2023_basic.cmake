# Juwels GCC with parastation  - v. 2023
# use with: 
# load modules:
#	    
#
#
set(CMAKE_Fortran_COMPILER "gfortran" ) # "ifort") #"gfortran")
set(Fortran_COMPILER_WRAPPER mpif90 ) # mpiifort)

set(USER_Fortran_FLAGS "-fbacktrace -finit-real=nan -fdefault-real-8  -fno-f2c -ffree-line-length-none -fallow-argument-mismatch")
set(USER_Fortran_FLAGS_RELEASE "-funroll-all-loops -O3 -fallow-argument-mismatch")
set(USER_Fortran_FLAGS_DEBUG "-W -Wall -Wuninitialized -fcheck=all -fbacktrace -O0 -g -fallow-argument-mismatch -ffpe-trap=invalid,zero,overflow")





