;-
;+
; :Description:
;    Describe the procedure.
;
; :Params:
;    vi_pix
;    qa_pix
;    doy_pix
;    nb
;    win_dim_l
;    win_dim_r
;    doys_reg
;    mapscape
;
; :Keywords:
;    check
;
; :Author: lb
;-
FUNCTION pr_smooth_pixel_v30_parline, lines, data_lc, data_VI, data_QA,data_DOY, nb, ncols,  win_dim_l,win_dim_r, doys_reg, years, proc_year, prev_y, mapscape

  COMPILE_OPT IDL2
  check = 0
  out_matrix = intarr(nb, ncols, n_elements(lines))

  IF MAPSCAPE EQ 1 THEN data_DOY[data_DOY EQ -1] = 32767

  ;- ------------------------------------------------------------------
  ; Reshuffle DOYS in case more than one year is on the required time serie + check and replace NODATA on DOYS
  ;- ------------------------------------------------------------------

  IF (min(years) LT proc_year) THEN BEGIN    ; If some bands of previous year required, compute their doy by subtracting 365

    ; Check with GT 12 needed because last doys of a year are set to small values if acquisition in day of composite in next year (e.g.,
    ; on the last image of the year (DOY = 361 or 356, if composition day is on the last "week", the real doy is in the next year and the
    ; value can be 3, or 4)

    prev_y_data = data_DOY[prev_y, *, *]
    prev_y_data[where(prev_y_data GT 12)] = prev_y_data[where(prev_y_data GT 12)] - 365
    data_DOY [prev_y, *, *  ] = prev_y_data
  ENDIF

  IF (max(years) GT proc_year) THEN BEGIN    ; If some bands of next year required, compute their doy by adding 365
    data_doy [where(years EQ proc_year +1),*, *] = data_DOY [where(years EQ proc_year +1),*, *] + 365
  ENDIF

  for line = 0, n_elements(lines)-1 DO BEGIN

    lc_line = data_lc [*,line]
    lc_ok = where(lc_line EQ 1, count_lc_ok, complement = lc_bad)   ; Find Pixels in the line with "good" lc values

;    smooth_line = smooth_dummy

    IF count_lc_ok GT 0 THEN BEGIN ; check on "land cover" mask. If no pixel in the line are "good", skip the line, otherwise, perform smooth
      ; on good pixels

      ; Cycle on pixels included in the lc_ok passed to the CPU

      ; Initialize output array
      out_line = intarr(nb, N_ELEMENTS(lc_ok))+32767

      for ind_pixel = 0, n_elements(lc_ok)-1 DO BEGIN

        pixel = lc_ok[ind_pixel]
        vi_pix = data_vi [*,pixel,line]       ; Retrieve vi, qa and doy for the pixel/line tuple
        qa_pix = data_QA [*,pixel, line]
        doy_pix = data_DOY [*,pixel,line]

        ; -------------------------------------------------
        ; ------ Initial checks on consistency of DOYs ----
        ; -------------------------------------------------

        ;  Substitute doys of where doy is nodata with doys_reg
        IF MAPSCAPE EQ 0 THEN BEGIN
          BAD_DOY = where(abs(DOY_PIX ) GT 1000, count_bad_doy)    ; Check on doys: doys > 400 = NODATA in DOY image --> set them to the doy of the composite
        ENDIF ELSE BEGIN
          BAD_DOY = where(DOY_PIX EQ -1, count_bad_doy)    ; Check on doys: doys > 400 = NODATA in DOY image --> set them to the doy of the composite !
        ENDELSE

        IF (count_bad_doy NE 0 ) THEN DOY_PIX[bad_doy] = doys_reg[bad_doy]

        ; Check for problems on DOYS: if difference between doy_pix and doys_reg LT -16 --> last doy_pixs wrong beacuase acquired in first days of "next year"
        ; --> Add 365 to the DOY
        diff = doy_pix-doys_reg
        bad_diff = where(diff LT -16, count_baddiff)
        IF (count_baddiff GT 0 ) THEN BEGIN
          doy_pix[bad_diff] = doy_pix[bad_diff]+365
        ENDIF

        ; Final check on doys. If still problems stop (Should never happen now !!!!)
        diff =max(abs(doy_pix-doys_reg))
        IF (diff GT 16) THEN BEGIN
          print, "Something wrong was found on the DOYS.... code to be recheked. contact cdevelopers @ lbusett@gmail.com"
          stop
        ENDIF

        IF (mapscape EQ 0) THEN nodata_pos = where(vi_pix EQ 32767, count_NA) ELSE nodata_pos = where(vi_pix EQ -3000, count_NA)  ; Check on vi values: vi = -3000 = NODATA .

        ; -------------------------------------------------
        ; ----------- Do the smoothing  -------------------
        ; -------------------------------------------------

        ; If more than 10 NODATA, skip the pixel and put it at 32767
        IF count_NA LT 10 THEN BEGIN          ; otherwise, perform smoothing

          ;------- SET WORKING ARRAYS. FLOAT/DOUBLE IS NEEDED BY SAVGOL INTERPOLATION:

          x_vect=[1,2,3,5,6,7]
          doys_ord = sort(doy_pix)
          vi_pix_ord = vi_pix[doys_ord]
          doy_pix_ord = doy_pix[doys_ord]
          qa_pix_ord = qa_pix[doys_ord]
          vi_pix_fl= vi_pix_ord
          dove_na = where(vi_pix_fl EQ 32767, count_na)
          x_vect=[1,2,3,5,6,7]


          ; 1) SPIKE DETECTION AND GAP FILLING
          time_serie_measure_errors = (200 * (qa_pix_ord EQ 0) + 1100 * (qa_pix_ord EQ 1) + 3000* (qa_pix_ord EQ 2))
          IF count_na GT 0 THEN BEGIN
            vi_pix_fl[dove_na] = 0
            time_serie_measure_errors [dove_na]= 7000
          ENDIF

          FOR K=win_dim_l, NB-(win_dim_r+1) DO BEGIN

            check_arr4 = vi_pix_ord[[k-2, k-1, k+1,k+2]]
            check_arr6 = vi_pix_ord[[k-3,k-2, k-1, k+1,k+2,k+3]]
            measure_errors= time_serie_measure_errors[[k-3,k-2, k-1, k+1,k+2,k+3]]
            MED_VAL=mean(CHECK_ARR4)
            STDEV_val=stdev(CHECK_ARR4)
            IF (vi_pix_ord[k] LT MED_VAL-2*STDEV_val) OR  (vi_pix_ord[k] GT MED_VAL+2*STDEV_val) THEN BEGIN

              ; OPTION 1 GAP FILLING:  SECOND ORDER POLINOMIAL
              result = poly_fit(x_vect, CHECK_ARR6, 2, MEASURE_ERRORS=measure_errors, Yfit = Yfit,/DOUBLE,status=status)
              time_serie_measure_errors[k] = 3000
              vi_pix_fl[k] = result[0]+RESULT[1]*4+RESULT[2]*(4^2)

            ENDIF
          ENDFOR

          ; 1) SAVGOL - first iteration - use weights derived from quality flags
          time_serie_y_new1=fltarr(nb)
          sum_index = indgen(win_dim_r*2+1)
          FOR k=0, nb-(win_dim_r*2+1) DO BEGIN

            smooth_indexes = k+sum_index
            Y=vi_pix_fl[smooth_indexes]
            x_vect = doy_pix_ord[smooth_indexes]
            x_vect_reg = doys_reg[smooth_indexes]
            measure_errors= time_serie_measure_errors[smooth_indexes]
            result = poly_fit(x_vect, Y, 2, MEASURE_ERRORS=measure_errors, Yfit = Yfit,status=status)
            time_serie_y_new1[K+win_dim_r]= Yfit[win_dim_r]

          ENDFOR

          ; put values "out" of the filtering (borders of TS) again at the original values
          time_serie_y_new1[0:(win_dim_r-1)] = vi_pix_ord[0:(win_dim_r-1)]
          time_serie_y_new1[(nb-win_dim_r):nb-1] = vi_pix_ord[(nb-win_dim_r):nb-1]

          ; 2) SAVGOL - second iteration - upper envelope adaptation
          ;
          old_vi = vi_pix_fl
          diff  = (time_serie_y_new1 - vi_pix_fl)
          diff[where(time_serie_measure_errors GT 10000*0.2)] = +0.01
          upper = where(diff LT 0, complement = pos_lower)
          time_serie_measure_errors [ upper ] = 200          ; set higher weights to where first run > orig to force towards upper envelope
          time_serie_measure_errors [ pos_lower ] = 500

          vi_pix_fl[pos_lower] = time_serie_y_new1[pos_lower] ; Set time series values of where first run < orig to first run, otherwise keep orig
          vi_pix_fl[0:(win_dim_r-1)] = vi_pix_ord[0:(win_dim_r-1)]    ; Reset the first and last values to the original VI values (so I don't have to set them to 0...)
          vi_pix_fl[(nb-win_dim_r):nb-1] = vi_pix_ord[(nb-win_dim_r):nb-1]
          time_serie_y_new2=fltarr(nb)

          FOR k=0, nb-(win_dim_r*2+1) DO BEGIN
            smooth_indexes = k+sum_index
            Y=vi_pix_fl[smooth_indexes]
            x_vect = doy_pix_ord[smooth_indexes]
            x_vect_reg = doys_reg[smooth_indexes]
            measure_errors= time_serie_measure_errors[smooth_indexes]
            result = poly_fit(x_vect, Y, 2, MEASURE_ERRORS=measure_errors, Yfit = Yfit,status=status)
            time_serie_y_new2[K+win_dim_r]= result[0]+RESULT[1]*x_vect_reg[3]+RESULT[2]*(x_vect_reg[3]^2)

          ENDFOR

          time_serie_y_new2[0:(win_dim_r-1)] = vi_pix_ord[0:(win_dim_r-1)]     ; Reset the first and last values to the original VI values (so I don't have to set them to 0...)
          time_serie_y_new2[(nb-win_dim_r):nb-1] = vi_pix_ord[(nb-win_dim_r):nb-1]

          out_matrix[*, pixel, line ] = fix(time_serie_y_new2)     ; Return smoothed array to caller !

        ENDIF ELSE BEGIN ; End if on less than 10 NA on VI series

          out_line[*, line, pixel] = dummy_pix

        ENDELSE

      ENDFOR

    ENDIF ELSE BEGIN

      out_matrix[*,*,line] = 32767   ; Put result of smoothed line in correct position

    ENDELSE


  ENDFOR

  return, out_matrix   ; send back result to the callue oBridge

END