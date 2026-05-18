!> \file modbulkcrosssection3.f90
!!   Dumps an instantenous crosssection of the field

!>
!! Dumps an instantenous crosssection of the scalar fields
!! basically a modified copy of 
!>
!! Crosssections in the yz-plane and in the xy-plane         |
    !        of scalar variables describing mixed-phase      |
    !        microphysics as well as remaining sv (1--nsv) varibles
    !        Written to hymovv_*.expnr and hymovh_*.expnr
!! If netcdf is true, this module leads to the hydrocross.myid.expnr.nc output

!!  \par Revision list
!  This file is part of DALES.
!
! DALES is free software; you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 3 of the License, or
! (at your option) any later version.
!
! DALES is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see <http://www.gnu.org/licenses/>.
!
!  Copyright 1993-2009 Delft University of Technology, Wageningen University, Utrecht University, KNMI
!
module modbulk3cross


  use modglobal, only : longint,kmax ! , nsv 
  use modmicrodata3, only : sb3nsv

implicit none
private
PUBLIC :: initbulk3cross, bulk3cross,exitbulk3cross ! initcrosssection, crosssection,exitcrosssection
save
!NetCDF variables
  integer,parameter  :: nvar = sb3nsv ! integer,parameter :: nvar = 12
  integer :: ncid1 = 0
  integer,allocatable :: ncid2(:)
  integer :: ncid3 = 1
  integer :: nrec1 = 0
  integer,allocatable :: nrec2(:)
  integer :: nrec3 = 0
  ! integer :: crossheight(100)
  integer :: nxy = 0
  integer :: cross
  character(4) :: cheight
  character(80) :: fname1 = 'hydrocrossxz.xxxxyxxx.xxx.nc'
  character(80) :: fname2 = 'hydrocrossxy.xxxx.xxxxyxxx.xxx.nc'
  character(80) :: fname3 = 'hydrocrossyz.xxxxyxxx.xxx.nc'
  character(80),dimension(nvar,4) :: ncname1
  character(80),dimension(1,4) :: tncname1
  character(80),dimension(nvar,4) :: ncname2
  character(80),dimension(1,4) :: tncname2
  character(80),dimension(nvar,4) :: ncname3
  character(80),dimension(1,4) :: tncname3

  real    :: dtav
  integer(kind=longint) :: idtav,tnext
  ! logical :: l_hcross = .false. !< switch for doing the crosssection (on/off)
  ! logical :: lbinary = .false. !< switch for doing the crosssection (on/off)
  ! integer :: crossplane = 2 !< Location of the xz crosssection
  ! integer :: crossortho = 2 !< Location of the yz crosssection

contains
!> Initializing Crosssection. Read out the namelist, initializing the variables
  subroutine initbulk3cross
    use modmpi,   only : myid,my_real,mpierr,comm3d,mpi_logical        &
                        ,mpi_integer,cmyid,myidx,myidy
    use modglobal,only : imax,jmax,ifnamopt,fname_options,dtmax        &
                        ,dtav_glob,ladaptive,j1,kmax,i1,dt_lim,cexpnr  &
                        ,tres,btime,checknamelisterror                 &
                        ,nsv
    use modstat_nc,only : lnetcdf,open_nc, define_nc,ncinfo,nctiminfo  &
                         ,writestat_dims_nc
    use modmicrodata3, only: l_hcross                                  & ! <-d- add flags
                            ,crossheight,crossplane, crossortho        & ! <-d- add settings 
                            ,dtav_hcross

   implicit none

    integer :: k, iisv    ! ierr,k
    character(3)  :: cnumsv
    character(80) :: cnamesv, cdescrsv

    !namelist/NAMCROSSSECTION/ &
    !l_hcross, lbinary, dtav, crossheight, crossplane, crossortho
    
    ! number of outputs
    ! nvar = nsv
    
    
    allocate(ncid2(kmax),nrec2(kmax))
    ! crossheight(1)=2
    ! crossheight(2:100)=-999
    ncid2(1)=2
    ncid2(2:kmax)=0
    nrec2(1:kmax)=0

    dtav = dtav_hcross ! dtav_glob
    
    
    !if(myid==0)then
    !  open(ifnamopt,file=fname_options,status='old',iostat=ierr)
    !  read (ifnamopt,NAMCROSSSECTION,iostat=ierr)
    !  call checknamelisterror(ierr, ifnamopt, 'NAMCROSSSECTION')
    !  write(6 ,NAMCROSSSECTION)
    !  close(ifnamopt)
    !end if

    !call MPI_BCAST(dtav       ,1,MY_REAL    ,0,comm3d,mpierr)
    !call MPI_BCAST(l_hcross     ,1,MPI_LOGICAL,0,comm3d,mpierr)
    !call MPI_BCAST(lbinary    ,1,MPI_LOGICAL,0,comm3d,mpierr)
    !call MPI_BCAST(crossheight(1:100),100,MPI_INTEGER,0,comm3d,mpierr)
    !call MPI_BCAST(crossplane ,1,MPI_INTEGER,0,comm3d,mpierr)
    !call MPI_BCAST(crossortho ,1,MPI_INTEGER,0,comm3d,mpierr)

    ! set up height and values
    nxy=0
    k=1
    do while (crossheight(k) > 0)
     nxy=nxy+1
     ncid2(k)=k+1
     nrec2(k)=0
     k=k+1
    end do

    idtav = dtav/tres
    tnext   = idtav+btime
    if(.not.(l_hcross)) return
    dt_lim = min(dt_lim,tnext)
    

    

    if(any((crossheight(1:100).gt.kmax)) .or. crossplane>j1 .or. crossortho> i1 ) then
      stop 'CROSSSECTION: bulk3cross out of range'
    end if
    if (.not. ladaptive .and. abs(dtav/dtmax-nint(dtav/dtmax))>1e-4) then
      stop 'CROSSSECTION: dtav should be a integer multiple of dtmax'
    end if
    
     
    if (lnetcdf) then
    if (myidy==0) then
      fname1(14:21) = cmyid   ! fname1(9:16) = cmyid
      fname1(23:25) = cexpnr ! fname1(18:20) = cexpnr
      call nctiminfo(tncname1(1,:))
      call ncinfo(ncname1( 1,:),'nrxz','xz crosssection of the Raindrop number concentration','/kg','t0tt')
      call ncinfo(ncname1( 2,:),'qrxz','xz crosssection of the Rain water specific humidity','kg/kg','t0tt')
      call ncinfo(ncname1( 3,:),'ncxz','xz crosssection of the Cloud droplet number concentration','/kg','t0tt')
      call ncinfo(ncname1( 4,:),'qcxz','xz crosssection of the Cloud liquid water specific humidity','kg/kg','t0tt')
      call ncinfo(ncname1( 5,:),'nixz','xz crosssection of the Cloud Ice crystal number concentration','/kg','t0tt')
      call ncinfo(ncname1( 6,:),'qixz','xz crosssection of the Cloud Ice specific humidity','kg/kg','t0tt')
      call ncinfo(ncname1( 7,:),'nsxz','xz crosssection of the Snow flake number concentration','/kg','t0tt')
      call ncinfo(ncname1( 8,:),'qsxz','xz crosssection of the Snow water specific humidity','kg/kg','t0tt')
      call ncinfo(ncname1( 9,:),'ngxz','xz crosssection of the Graupel number concentration','/kg','t0tt')
      call ncinfo(ncname1(10,:),'qgxz','xz crosssection of the Graupel water specific humidity','kg/kg','t0tt')
      call ncinfo(ncname1(11,:),'nccnxz','xz crosssection of the CCN number concentration','/kg','t0tt')
      call ncinfo(ncname1(12,:),'ninpxz','xz crosssection of the INP number concentration','/kg','t0tt')
      ! and additional variable names 
       
      if (nvar.gt.sb3nsv) then
        do iisv=  sb3nsv, nvar ! <-- change this if needed 
          write(cnumsv,'(i3.3)') iisv  ! get number as string 
          ! variable name
          cnamesv(1:2) = 'sv'
          cnamesv(3:5) = cnumsv
          cnamesv(6:7) = 'xz'
          cdescrsv(1:21) = 'xz crosssection of sv'
          cdescrsv(22:24) = cnumsv
          ! output it
          call ncinfo(ncname1(iisv,:),cnamesv,cdescrsv,'/kg','t0tt')
        end do
      end if
      
      call open_nc(fname1,  ncid1,nrec1,n1=imax,n3=kmax)
      if (nrec1 == 0) then
        call define_nc( ncid1, 1, tncname1)
        call writestat_dims_nc(ncid1)
      end if
      call define_nc( ncid1, NVar, ncname1)
      
    end if
    do cross=1,nxy
      write(cheight,'(i4.4)') crossheight(cross)
      fname2(14:17) = cheight  ! fname2(9:12) = cheight
      fname2(19:26) = cmyid   ! fname2(14:21) = cmyid
      fname2(28:30) = cexpnr  ! fname2(23:25) = cexpnr
      call nctiminfo(tncname2(1,:))
      !call ncinfo(ncname2( 9,:),'qrxy','xy crosssection of the Rain water specific humidity','kg/kg','tt0t')
      call ncinfo(ncname2( 1,:),'nrxy','xy crosssection of the Raindrop number concentration','/kg','tt0t')
      call ncinfo(ncname2( 2,:),'qrxy','xy crosssection of the Rain water specific humidity','kg/kg','tt0t')
      call ncinfo(ncname2( 3,:),'ncxy','xy crosssection of the Cloud droplet number concentration','/kg','tt0t')
      call ncinfo(ncname2( 4,:),'qcxy','xy crosssection of the Cloud liquid water specific humidity','kg/kg','tt0t')
      call ncinfo(ncname2( 5,:),'nixy','xy crosssection of the Cloud Ice crystal number concentration','/kg','tt0t')
      call ncinfo(ncname2( 6,:),'qixy','xy crosssection of the Cloud Ice specific humidity','kg/kg','tt0t')
      call ncinfo(ncname2( 7,:),'nsxy','xy crosssection of the Snow flake number concentration','/kg','tt0t')
      call ncinfo(ncname2( 8,:),'qsxy','xy crosssection of the Snow water specific humidity','kg/kg','tt0t')
      call ncinfo(ncname2( 9,:),'ngxy','xy crosssection of the Graupel number concentration','/kg','tt0t')
      call ncinfo(ncname2(10,:),'qgxy','xy crosssection of the Graupel water specific humidity','kg/kg','tt0t')
      call ncinfo(ncname2(11,:),'nccnxy','xy crosssection of the CCN number concentration','/kg','tt0t')
      call ncinfo(ncname2(12,:),'ninpxy','xy crosssection of the INP number concentration','/kg','tt0t')
      ! and additional variable names 
      if (nvar.gt.sb3nsv) then
        do iisv=  sb3nsv, nvar ! <-- change this if needed 
          write(cnumsv,'(i3.3)') iisv  ! get number as string 
          ! variable name
          cnamesv(1:2) = 'sv'
          cnamesv(3:5) = cnumsv
          cnamesv(6:7) = 'xy'
          cdescrsv(1:21) = 'xy crosssection of sv'
          cdescrsv(22:24) = cnumsv
          ! output it
          call ncinfo(ncname2(iisv,:),cnamesv,cdescrsv,'/kg','tt0t')
        end do
      end if
      call open_nc(fname2,  ncid2(cross),nrec2(cross),n1=imax,n2=jmax)
      if (nrec2(cross)==0) then
        call define_nc( ncid2(cross), 1, tncname2)
        call writestat_dims_nc(ncid2(cross))
      end if
      call define_nc( ncid2(cross), NVar, ncname2)
      
   end do
   if (myidx==0) then
    fname3(14:21) = cmyid   ! fname3(9:16) = cmyid
    fname3(23:25) = cexpnr ! fname3(18:20) = cexpnr
    call nctiminfo(tncname3(1,:))
    !call ncinfo(ncname3( 9,:),'qryz','yz crosssection of the Rain water specific humidity','kg/kg','0ttt')
      call ncinfo(ncname3( 1,:),'nryz','yz crosssection of the Raindrop number concentration','/kg','0ttt')
      call ncinfo(ncname3( 2,:),'qryz','yz crosssection of the Rain water specific humidity','kg/kg','0ttt')
      call ncinfo(ncname3( 3,:),'ncyz','yz crosssection of the Cloud droplet number concentration','/kg','0ttt')
      call ncinfo(ncname3( 4,:),'qcyz','yz crosssection of the Cloud liquid water specific humidity','kg/kg','0ttt')
      call ncinfo(ncname3( 5,:),'niyz','yz crosssection of the Cloud Ice crystal number concentration','/kg','0ttt')
      call ncinfo(ncname3( 6,:),'qiyz','yz crosssection of the Cloud Ice specific humidity','kg/kg','0ttt')
      call ncinfo(ncname3( 7,:),'nsyz','yz crosssection of the Snow flake number concentration','/kg','0ttt')
      call ncinfo(ncname3( 8,:),'qsyz','yz crosssection of the Snow water specific humidity','kg/kg','0ttt')
      call ncinfo(ncname3( 9,:),'ngyz','yz crosssection of the Graupel number concentration','/kg','0ttt')
      call ncinfo(ncname3(10,:),'qgyz','yz crosssection of the Graupel water specific humidity','kg/kg','0ttt')
      call ncinfo(ncname3(11,:),'nccnyz','yz crosssection of the CCN number concentration','/kg','0ttt')
      call ncinfo(ncname3(12,:),'ninpyz','yz crosssection of the INP number concentration','/kg','0ttt')
    ! and additional variable names 
    if (nvar.gt.sb3nsv) then
        do iisv=  sb3nsv, nvar ! <-- change this if needed 
          write(cnumsv,'(i3.3)') iisv  ! get number as string 
          ! variable name
          cnamesv(1:2) = 'sv'
          cnamesv(3:5) = cnumsv
          cnamesv(6:7) = 'xz'
          cdescrsv(1:21) = 'xz crosssection of sv'
          cdescrsv(22:24) = cnumsv
          ! output it
          call ncinfo(ncname3(iisv,:),cnamesv,cdescrsv,'/kg','0ttt')
        end do
    end if
    call open_nc(fname3,  ncid3,nrec3,n2=jmax,n3=kmax)
    if (nrec3==0) then
      call define_nc( ncid3, 1, tncname3)
      call writestat_dims_nc(ncid3)
    end if
    call define_nc( ncid3, NVar, ncname3)
    
   end if
    
 end if


  end subroutine initbulk3cross
!>Run crosssection. Mainly timekeeping
  subroutine bulk3cross
    use modglobal, only : rk3step,timee,dt_lim
    use modstat_nc, only : writestat_nc
    use modmicrodata3, only: l_hcross                                  &   ! <-d- add flags
                            ,crossheight,crossplane, crossortho
    implicit none


    if (.not. l_hcross) return
    if (rk3step/=3) return
    if(timee<tnext) then
      dt_lim = min(dt_lim,tnext-timee)
      return
    end if
    tnext = tnext+idtav
    dt_lim = minval((/dt_lim,tnext-timee/))

    call wrt3vert
    call wrt3horz
    call wrt3orth

  end subroutine bulk3cross


!> Do the xz crosssections and dump them to file
  subroutine wrt3vert
  use modglobal, only : imax,i1,kmax,nsv,cexpnr,ifoutput,rtimee      ! rlv,cp,rv,rd,cu,cv,
  use modfields, only : svm   !  um,vm,wm,thlm,qtm,thl0,qt0,ql0,e120,exnf,thvf,cloudnr
  use modmpi,    only : myidy
  use modstat_nc, only : lnetcdf, writestat_nc
  use modmicrodata3, only: crossplane                                 &
                          ,in_hr, in_cl, in_ci, in_hs, in_hg          &
                          ,iq_hr, iq_cl, iq_ci, iq_hs, iq_hg          &
                          ,in_cc, in_in, sb3nsv
  implicit none

  integer i,k,n, iisv
  character(20) :: name

  real, allocatable :: vars(:,:,:) !real, allocatable :: thv0(:,:),vars(:,:,:),buoy(:,:)

  if( myidy /= 0 ) return 

  !allocate(thv0(2:i1,1:kmax),buoy(2:i1,1:kmax))


    !do  i=2,i1
    !do  k=1,kmax
    !  thv0(i,k) = (thl0(i,crossplane,k)+rlv*ql0(i,crossplane,k)/(cp*exnf(k))) &
    !                *(1+(rv/rd-1)*qt0(i,crossplane,k)-rv/rd*ql0(i,crossplane,k))
    !  buoy(i,k) = thv0(i,k)-thvf(k)
    !enddo
    !enddo

!     if(lbinary) then
!       open(ifoutput,file='movv_u.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((um(i,crossplane,k)+cu,i=2,i1),k=1,kmax)
!       close(ifoutput)
! 
!       open(ifoutput,file='movv_v.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((vm(i,crossplane,k)+cv,i=2,i1),k=1,kmax)
!       close(ifoutput)
! 
!       open(ifoutput,file='movv_w.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((wm(i,crossplane,k),i=2,i1),k=1,kmax)
!       close(ifoutput)
! 
!       open(ifoutput,file='movv_thl.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((thlm(i,crossplane,k),i=2,i1),k=1,kmax)
!       close(ifoutput)
! 
!       open(ifoutput,file='movv_thv.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((thv0(i,k),i=2,i1),k=1,kmax)
!       close(ifoutput)
! 
!       open(ifoutput,file='movv_buoy.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((buoy(i,k),i=2,i1),k=1,kmax)
!       close(ifoutput)
! 
!       open(ifoutput,file='movv_qt.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((1.e3*qtm(i,crossplane,k),i=2,i1),k=1,kmax)
!       close(ifoutput)
! 
!       open(ifoutput,file='movv_ql.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((1.e3*ql0(i,crossplane,k),i=2,i1),k=1,kmax)
!       close(ifoutput)
! 
!       do n = 1,nsv
!         name = 'movh_tnn.'//cexpnr
!         write(name(7:8),'(i2.2)') n
!         open(ifoutput,file=name,position='append',action='write')
!         write(ifoutput,'(es12.5)') ((svm(i,crossplane,k,n),i=2,i1),k=1,kmax)
!         close(ifoutput)
!       end do
!     end if

    if (lnetcdf) then
      allocate(vars(1:imax,1:kmax,nvar))
      vars(:,:,1) = svm(2:i1,crossplane,1:kmax,in_hr)! um(2:i1,crossplane,1:kmax)+cu
      vars(:,:,2) = svm(2:i1,crossplane,1:kmax,iq_hr)
      vars(:,:,3) = svm(2:i1,crossplane,1:kmax,in_cl)
      vars(:,:,4) = svm(2:i1,crossplane,1:kmax,iq_cl)
      vars(:,:,5) = svm(2:i1,crossplane,1:kmax,in_ci)
      vars(:,:,6) = svm(2:i1,crossplane,1:kmax,iq_ci)
      vars(:,:,7) = svm(2:i1,crossplane,1:kmax,in_hs)
      vars(:,:,8) = svm(2:i1,crossplane,1:kmax,iq_hs)
      vars(:,:,9) = svm(2:i1,crossplane,1:kmax,in_hg)
      vars(:,:,10) = svm(2:i1,crossplane,1:kmax,iq_hg)
      vars(:,:,11) = svm(2:i1,crossplane,1:kmax,in_cc)
      vars(:,:,12) = svm(2:i1,crossplane,1:kmax,in_in)
      if(nvar .gt. sb3nsv) then
       !vars(:,:,9) = svm(2:i1,crossplane,1:kmax,2)
       do iisv = sb3nsv, nvar
         vars(:,:,iisv) = svm(2:i1,crossplane,1:kmax,iisv) 
       end do
      end if
      call writestat_nc(ncid1,1,tncname1,(/rtimee/),nrec1,.true.)
      call writestat_nc(ncid1,nvar,ncname1(1:nvar,:),vars,nrec1,imax,kmax)
      deallocate(vars)
    end if
    ! deallocate(thv0,buoy)

  end subroutine wrt3vert

!> Do the xy crosssections and dump them to file
  subroutine wrt3horz
    use modglobal, only : imax,jmax,i1,j1,nsv,cexpnr,ifoutput,rtimee ! rlv,cp,rv,rd,cu,cv,
    use modfields, only : svm ! um,vm,wm,thlm,qtm,thl0,qt0,ql0,e120,exnf,thvf,cloudnr
    use modmpi,    only : cmyid
    use modstat_nc, only : lnetcdf, writestat_nc
    use modmicrodata3, only: crossheight                                &
                            ,in_hr, in_cl, in_ci, in_hs, in_hg          &
                            ,iq_hr, iq_cl, iq_ci, iq_hs, iq_hg          &
                            ,in_cc, in_in, sb3nsv
    implicit none


    ! LOCAL
    integer i,j,n, iisv
    character(40) :: name
    real, allocatable :: vars(:,:,:) ! real, allocatable :: thv0(:,:,:),vars(:,:,:),buoy(:,:,:)

    ! allocate(thv0(2:i1,2:j1,nxy),buoy(2:i1,2:j1,nxy))

    !do  cross=1,nxy
    !do  j=2,j1
    !do  i=2,i1
    !  thv0(i,j,cross) =&
    !   (thl0(i,j,crossheight(cross))+&
    !   rlv*ql0(i,j,crossheight(cross))/&
    !   (cp*exnf(crossheight(cross)))) &
    !                *(1+(rv/rd-1)*qt0(i,j,crossheight(cross))&
    !                -rv/rd*ql0(i,j,crossheight(cross)))
    !  buoy(i,j,cross) =thv0(i,j,cross)-thvf(crossheight(cross))
    !enddo
    !enddo
    !enddo

!     if(lbinary) then
!       do  cross=1,nxy
!       write(cheight,'(i4.4)') crossheight(cross)
!       open(ifoutput,file='movh_u.'//cheight//'.'//cmyid//'.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((um(i,j,crossheight(cross))+cu,i=2,i1),j=2,j1)
!       close(ifoutput)
! 
!       open(ifoutput,file='movh_v.'//cheight//'.'//cmyid//'.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((vm(i,j,crossheight(cross))+cv,i=2,i1),j=2,j1)
!       close(ifoutput)
! 
!       open(ifoutput,file='movh_w.'//cheight//'.'//cmyid//'.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((wm(i,j,crossheight(cross)),i=2,i1),j=2,j1)
!       close(ifoutput)
! 
!       open(ifoutput,file='movh_thl.'//cheight//'.'//cmyid//'.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((thlm(i,j,crossheight(cross)),i=2,i1),j=2,j1)
!       close(ifoutput)
! 
!       open(ifoutput,file='movh_thv.'//cheight//'.'//cmyid//'.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((thv0(i,j,cross),i=2,i1),j=2,j1)
!       close(ifoutput)
! 
!       open(ifoutput,file='movh_buoy.'//cheight//'.'//cmyid//'.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((buoy(i,j,cross),i=2,i1),j=2,j1)
!       close(ifoutput)
! 
!       open(ifoutput,file='movh_qt.'//cheight//'.'//cmyid//'.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((1.e3*qtm(i,j,crossheight(cross)),i=2,i1),j=2,j1)
!       close(ifoutput)
! 
!       open(ifoutput,file='movh_ql.'//cheight//'.'//cmyid//'.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((1.e3*ql0(i,j,crossheight(cross)),i=2,i1),j=2,j1)
!       close(ifoutput)
! 
!       do n = 1,nsv
!         name = 'movh_snn.'//trim(cheight)//'.'//cmyid//'.'//cexpnr
!         write(name(7:8),'(i2.2)') n
!         open(ifoutput,file=name,position='append',action='write')
!         write(ifoutput,'(es12.5)') ((svm(i,j,crossheight(cross),n),i=2,i1),j=2,j1)
!         close(ifoutput)
!       end do
!       end do
!     endif

    if (lnetcdf) then
      do cross=1,nxy
      allocate(vars(1:imax,1:jmax,nvar))
      vars=0.
      !vars(:,:,10) = svm(2:i1,2:j1,crossheight(cross),inr)
      vars(:,:,1) = svm(2:i1,2:j1,crossheight(cross),in_hr)
      vars(:,:,2) = svm(2:i1,2:j1,crossheight(cross),iq_hr)
      vars(:,:,3) = svm(2:i1,2:j1,crossheight(cross),in_cl)
      vars(:,:,4) = svm(2:i1,2:j1,crossheight(cross),iq_cl)
      vars(:,:,5) = svm(2:i1,2:j1,crossheight(cross),in_ci)
      vars(:,:,6) = svm(2:i1,2:j1,crossheight(cross),iq_ci)
      vars(:,:,7) = svm(2:i1,2:j1,crossheight(cross),in_hs)
      vars(:,:,8) = svm(2:i1,2:j1,crossheight(cross),iq_hs)
      vars(:,:,9) = svm(2:i1,2:j1,crossheight(cross),in_hg)
      vars(:,:,10) = svm(2:i1,2:j1,crossheight(cross),iq_hg)
      vars(:,:,11) = svm(2:i1,2:j1,crossheight(cross),in_cc)
      vars(:,:,12) = svm(2:i1,2:j1,crossheight(cross),in_in)      
      if(nvar .gt. sb3nsv) then
       do iisv = sb3nsv, nvar
         vars(:,:,iisv) = svm(2:i1,2:j1,crossheight(cross),iisv) 
       end do
      end if
      call writestat_nc(ncid2(cross),1,tncname2,(/rtimee/),nrec2(cross),.true.)
      call writestat_nc(ncid2(cross),nvar,ncname2(1:nvar,:),vars,nrec2(cross),imax,jmax)
      deallocate(vars)
      end do
    end if

    !deallocate(thv0,buoy)

  end subroutine wrt3horz

  ! yz cross section
  subroutine wrt3orth
    use modglobal, only : jmax,kmax,j1,nsv,cexpnr,ifoutput,rtimee ! rlv,cp,rv,rd,cu,cv,
    use modfields, only : svm  ! um,vm,wm,thlm,qtm,thl0,qt0,ql0,e120,exnf,thvf,cloudnr
    use modmpi,    only : cmyid, myidx
    use modstat_nc, only : lnetcdf, writestat_nc
    use modmicrodata3, only: crossortho                               &
                            ,in_hr, in_cl, in_ci, in_hs, in_hg        &
                            ,iq_hr, iq_cl, iq_ci, iq_hs, iq_hg        &
                            ,in_cc, in_in, sb3nsv
    implicit none


    ! LOCAL
    integer j,k,n, iisv
    character(21) :: name

    real, allocatable :: vars(:,:,:) !real, allocatable :: thv0(:,:),vars(:,:,:),buoy(:,:)

    if( myidx /= 0 ) return 


    !allocate(thv0(1:j1,1:kmax),buoy(1:j1,1:kmax))
    !
    !do  j=1,j1
    !do  k=1,kmax
    !  thv0(j,k) =&
    !   (thl0(crossortho,j,k)+&
    !   rlv*ql0(crossortho,j,k)/&
    !   (cp*exnf(k))) &
    !                *(1+(rv/rd-1)*qt0(crossortho,j,k)&
    !                -rv/rd*ql0(crossortho,j,k))
    !   buoy(j,k) =thv0(j,k)-thvf(k)
    !enddo
    !enddo

!     if(lbinary) then
!       open(ifoutput,file='movo_u.'//cmyid//'.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((um(crossortho,j,k)+cu,j=2,j1),k=1,kmax)
!       close(ifoutput)
! 
!       open(ifoutput,file='movo_v.'//cmyid//'.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((vm(crossortho,j,k)+cv,j=2,j1),k=1,kmax)
!       close(ifoutput)
! 
!       open(ifoutput,file='movo_w.'//cmyid//'.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((wm(crossortho,j,k),j=2,j1),k=1,kmax)
!       close(ifoutput)
! 
!       open(ifoutput,file='movo_thl.'//cmyid//'.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((thlm(crossortho,j,k),j=2,j1),k=1,kmax)
!       close(ifoutput)
! 
!       open(ifoutput,file='movo_thv.'//cmyid//'.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((thv0(j,k),j=2,j1),k=1,kmax)
!       close(ifoutput)
! 
!       open(ifoutput,file='movo_buoy.'//cmyid//'.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((buoy(j,k),j=2,j1),k=1,kmax)
!       close(ifoutput)
! 
!       open(ifoutput,file='movo_qt.'//cmyid//'.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((1.e3*qtm(crossortho,j,k),j=2,j1),k=1,kmax)
!       close(ifoutput)
! 
!       open(ifoutput,file='movo_ql.'//cmyid//'.'//cexpnr,position='append',action='write')
!       write(ifoutput,'(es12.5)') ((1.e3*ql0(crossortho,j,k),j=2,j1),k=1,kmax)
!       close(ifoutput)
! 
!       do n = 1,nsv
!         name = 'movh_tnn.'//cmyid//'.'//cexpnr
!         write(name(7:8),'(i2.2)') n
!         open(ifoutput,file=name,position='append',action='write')
!         write(ifoutput,'(es12.5)') ((svm(crossortho,j,k,n),j=2,j1),k=1,kmax)
!         close(ifoutput)
!       end do
!     end if

    if (lnetcdf) then
      allocate(vars(1:jmax,1:kmax,nvar))
      ! vars(:,:,10) = svm(crossortho,2:j1,1:kmax,1)
      vars(:,:,1) = svm(crossortho,2:j1,1:kmax,in_hr)
      vars(:,:,2) = svm(crossortho,2:j1,1:kmax,iq_hr)
      vars(:,:,3) = svm(crossortho,2:j1,1:kmax,in_cl)
      vars(:,:,4) = svm(crossortho,2:j1,1:kmax,iq_cl)
      vars(:,:,5) = svm(crossortho,2:j1,1:kmax,in_ci)
      vars(:,:,6) = svm(crossortho,2:j1,1:kmax,iq_ci)
      vars(:,:,7) = svm(crossortho,2:j1,1:kmax,in_hs)
      vars(:,:,8) = svm(crossortho,2:j1,1:kmax,iq_hs)
      vars(:,:,9) = svm(crossortho,2:j1,1:kmax,in_hg)
      vars(:,:,10) = svm(crossortho,2:j1,1:kmax,iq_hg)
      vars(:,:,11) = svm(crossortho,2:j1,1:kmax,in_cc)
      vars(:,:,12) = svm(crossortho,2:j1,1:kmax,in_in)
      if(nvar .gt. sb3nsv) then
       do iisv = sb3nsv, nvar
         vars(:,:,iisv) = svm(crossortho,2:j1,1:kmax,iisv) 
       end do
      end if     
      call writestat_nc(ncid3,1,tncname3,(/rtimee/),nrec3,.true.)
      call writestat_nc(ncid3,nvar,ncname3(1:nvar,:),vars,nrec3,jmax,kmax)
      deallocate(vars)
    end if

    ! deallocate(thv0,buoy)

  end subroutine wrt3orth

!> Clean up when leaving the run
  subroutine exitbulk3cross
    use modstat_nc, only : exitstat_nc,lnetcdf
    use modmpi, only : myidx, myidy
    use modmicrodata3, only: l_hcross ! <-- add flags
    implicit none

    if(l_hcross .and. lnetcdf) then
    if (myidy==0) then
       call exitstat_nc(ncid1)
    end if
    do cross=1,nxy
    call exitstat_nc(ncid2(cross))
    end do
    if (myidx==0) then
       call exitstat_nc(ncid3)
    end if    
    end if

  end subroutine exitbulk3cross

end module modbulk3cross
