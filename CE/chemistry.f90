!=======================================================================
!> @file chemistry.f90
!> @brief chemistry  module
!> @author A. Castellanos, P. Rivera A. Rodriguez, A. Raga  and A. Esquivel
!> @date 10/Mar/2016

! Copyright (c) 2016 A. Esquivel et al.
!
! This file is part of Guacho-3D.
!
! Guacho-3D is free software; you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 3 of the License, or
! (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
! GNU General Public License for more details.
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see http://www.gnu.org/licenses/.
!=======================================================================

!> @brief chemistry module
!> @details module to solve the chemical/ionic network.

module chemistry

  use network
  implicit none
  integer :: failed_convergence

contains

!=======================================================================


!> @brief Advances the chemistry network
!> @details Advances the chemistry network on the entire domain
!> (except ghost cells), updates primitives and conserved variables
!> in globals

subroutine update_chem()

  use parameters, only : neq, neqdyn, nx, ny, nz, tsc, rhosc,  &
                      nxtot, nytot, nztot
  use globals, only : u, primit, dt_CFL, coords, dx, dy, dz, rank,
  use network, only : n_spec, n_elem, n1_chem
  use hydro_core, only : u2prim
  use difrad, only : phCold, phHot
  use exoplanet, only : RSW
  implicit none
  real :: dt_seconds, T, y(n_spec), y0(n_elem)
  integer :: i, j, k, l
  real    :: x, y, z, rads

  dt_seconds = dt_CFL*tsc
  failed_convergence = 0.

  do k=1,nz
    do j=1,ny
      do i=1,nx

        ! Position measured from the centre of the grid (star)
        x=(real(i+coords(0)*nx-nxtot/2)-0.5)*dx
        y=(real(j+coords(1)*ny-nytot/2)-0.5)*dy
        z=(real(k+coords(2)*nz-nztot/2)-0.5)*dz

        !   get the primitives (and T)
        call u2prim(u(:,i,j,k),primit(:,i,j,k),T)
        y(1:n_spec) = primit(n1_chem: n1_chem+n_spec-1,i,j,k)
        y0(1      ) = primit(1,i,j,k)
        !  update the passive primitives (should not work in single precision)

        ! Distance from the centre of the star
        rads=sqrt(x**2+y**2+z**2)
        ! IF INSIDE THE STAR
        if( rads < rsw) then
          !call chemstep(primit( (neqdyn+1):(neqdyn+n_spec),i,j,k), primit(1,i,j,k), T, dt_seconds )
          call chemstep(y, y0, T, dt_seconds,phHot(i,j,k),phCold(i,j,k))

        end if
          !  update the primitives and conserved variables
        do l = 1, n_spec
          primit(n1_chem+l-1, i,j,k) = y(l)
          u     (n1_chem+l-1, i,j,k) = y(l)
        end do

        primit(6,i,j,k)  = y(Hh0) + y(Hc0)
        u(6,i,j,k)       = y(Hh0) + y(Hc0)

      end do
    end do
  end do

  if (failed_convergence > 0) print'(a,i3,a,i,a)', 'in rank: ', rank, 'chemistry convergence failed in ', failed_convergence, ' cells'

end subroutine update_chem


!=======================================================================

!> @brief Advances the chemistry network in one cell
!> @details Advances the chemistry network on the in one cell
!> @param real [inout] y(n_spec) : number densities of the species
!> to be updated by the chemistry
!> @param real [in] y[n_elem] : total number density of each of the
!> elements involved in the reactions
!> @param real [in] T : Temperature [K]
!> @param real [in] deltt : time interval (from the hydro, in seconds)

subroutine chemstep(y,y0,T, deltt,phiH, phiC)
  use linear_system
  use network, only : n_spec, n_reac, n_elem, get_reaction_rates,  &
                      derv, get_jacobian, n_nequ, check_no_conservation
  implicit none
  real (kind=8), intent(inout) :: y(n_spec)
  real (kind=8), intent(in) ::    y0(n_elem), T, deltt  , phiH, phiC
  real (kind=8) :: dtm
  real (kind=8) :: y1(n_spec),yt(n_spec),yin(n_spec), y0_in(n_elem)
  real (kind=8) :: rate(n_reac),dydt(n_spec),jac(n_spec,n_spec)
  integer, parameter  :: niter=100       ! number of iterations
  integer :: n,i,iff

  n=0
  dtm=1./deltt
  iff=1
  yin(:) =y (:)
  y0_in(:) = y0(:)

  call get_reaction_rates(rate,T,phiH, phiC)

  !  initial guess for Newton-Raphson
  if ( check_no_conservation(y,y0_in) ) then
    !print*, '*****Reset Initial Guess ********'
    !print*, "T=", T
    call nr_init(y,y0_in)
  end if

  do while ( n <= niter )

    call derv(y,rate,dydt,y0)
    call get_jacobian(y,jac,rate)

    do i=1,n_nequ
      jac(i,i)=jac(i,i)-dtm
      dydt(i)=dydt(i)-(y(i)-yin(i))*dtm
    end do
    y1(:)=-dydt(:)

    call linsys(jac,y1, n_spec)

    y(:)=y(:) + y1(:)
    y(:)=max(y(:),1.e-40)

    yt(:)=y1(:)/y(:)

    !  exit the loop if converged
    if(all(abs(y1(:)) <= 0.0001)) exit

    n=n+1

  end do

  if (n >= niter) then
    failed_convergence = failed_convergence + 1
  !  print*, "failed to converge after ", niter, " iterations"
  !else
  !  print*, 'converged after ', n+1, ' iterations'
  end if

  return

end subroutine chemstep

!=======================================================================

  end module chemistry
