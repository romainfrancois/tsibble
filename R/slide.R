# nocov start
replace_fn_names <- function(fn, replace = list(), ns = NULL) {
  rec_fn <- function(cl) {
    if (!is_call(cl)) {
      return(cl)
    }
    args_lst <- lapply(as.list(cl[-1]), rec_fn)
    if (any(repl_fn <- names(replace) %in% call_name(cl))) {
      cl[[1]] <- replace[[repl_fn]]
      cl <- call2(cl[[1]], !!! args_lst, .ns = ns)
    } else {
      cl <- call2(cl[[1]], !!! args_lst)
    }
  }
  body(fn) <- rec_fn(body(fn))
  fn
}
# nocov end

#' Sliding window calculation
#'
#' Rolling window with overlapping observations:
#' * `slide()` always returns a list.
#' * `slide_lgl()`, `slide_int()`, `slide_dbl()`, `slide_chr()` use the same
#' arguments as `slide()`, but return vectors of the corresponding type.
#' * `slide_dfr()` & `slide_dfc()` return data frames using row-binding & column-binding.
#'
#' @param .x An object to slide over.
#' @inheritParams purrr::map
#' @param .size An integer for window size. If positive, moving forward from left
#' to right; if negative, moving backward (from right to left).
#' @param .fill A value to fill at the left of the data range (`NA` by default).
#' `NULL` means no filling.
#' @param .partial if `TRUE`, partial sliding.
#' @param .align Align index at the "**r**ight", "**c**entre"/"center", or "**l**eft"
#' of the window. If `.size` is even for center alignment, "centre-right" & "centre-left"
#' is needed.
#' @param .bind If `.x` is a list, should `.x` be combined before applying `.f`?
#' If `.x` is a list of data frames, row binding is carried out.
#'
#' @rdname slide
#' @export
#' @family sliding window functions
#' @seealso
#' * [future_slide] for parallel processing
#' * [tile] for tiling window without overlapping observations
#' * [stretch] for expanding more observations
#' @details The `slide()` function attempts to tackle more general problems using
#' the purrr-like syntax. For some specialist functions like `mean` and `sum`,
#' you may like to check out for **RcppRoll** for faster performance.
#'
#' `slide()` is intended to work with list (and column-wise data frame). To
#' perform row-wise sliding window on data frame, please check out [pslide()].
#'
#' * `.partial = TRUE` allows for partial sliding. Window contains observations 
#' outside of the vector will be treated as value of `.fill`, which will be passed to `.f`.
#' * `.partial = FALSE` restricts calculations to be done on complete sliding windows. 
#' Window contains observations outside of the vector will return the value `.fill`.
#'
#' @examples
#' x <- 1:5
#' lst <- list(x = x, y = 6:10, z = 11:15)
#' slide_dbl(x, mean, .size = 2)
#' slide_dbl(x, mean, .size = 2, align = "center")
#' slide_lgl(x, ~ mean(.) > 2, .size = 2)
#' slide(lst, ~ ., .size = 2)
slide <- function(
  .x, .f, ..., .size = 1, .fill = NA, .partial = FALSE, 
  .align = "right", .bind = FALSE
) {
  if (.partial) {
    lst_x <- partial_slider(
      .x, .size = .size, .fill = .fill, .align = .align, .bind = .bind
    )
  } else {
    lst_x <- slider(.x, .size = .size, .bind = .bind)
  }
  out <- map(lst_x, .f, ...)
  if (.partial) {
    out
  } else {
    pad_slide(out, .size, .fill, .align)
  }
}

#' @evalRd paste0('\\alias{slide_', c("lgl", "chr", "int", "dbl"), '}')
#' @name slide
#' @rdname slide
#' @exportPattern ^slide_
for(type in c("lgl", "chr", "int", "dbl")){
  assign(
    paste0("slide_", type),
    replace_fn_names(slide, list(map = paste0("map_", type)))
  )
}

#' @rdname slide
#' @export
slide_dfr <- function(
  .x, .f, ..., .size = 1, .fill = NA, .partial = FALSE, .align = "right", 
  .bind = FALSE, .id = NULL
) {
  out <- slide(
    .x, .f = .f, ..., 
    .size = .size, .fill = .fill, .partial = .partial, 
    .align = .align, .bind = .bind
  )
  bind_df(out, .size, .fill, .id = .id)
}

#' @rdname slide
#' @export
slide_dfc <- function(
  .x, .f, ..., .size = 1, .fill = NA, .partial = FALSE, 
  .align = "right", .bind = FALSE
) {
  out <- slide(
    .x, .f = .f, ..., 
    .size = .size, .fill = .fill, .partial = .partial, 
    .align = .align, .bind = .bind
  )
  bind_df(out, .size, .fill, byrow = FALSE)
}

#' Sliding window calculation over multiple inputs simultaneously
#'
#' Rolling window with overlapping observations:
#' * `slide2()` and `pslide()` always returns a list.
#' * `slide2_lgl()`, `slide2_int()`, `slide2_dbl()`, `slide2_chr()` use the same
#' arguments as `slide2()`, but return vectors of the corresponding type.
#' * `slide2_dfr()` `slide2_dfc()` return data frames using row-binding & column-binding.
#'
#' @param .x,.y Objects to slide over simultaneously.
#' @inheritParams slide
#'
#' @rdname slide2
#' @export
#' @family sliding window functions
#' @seealso
#' * [tile2] for tiling window without overlapping observations
#' * [stretch2] for expanding more observations
#'
#' @export
#' @examples
#' x <- 1:5
#' y <- 6:10
#' z <- 11:15
#' lst <- list(x = x, y = y, z = z)
#' df <- as.data.frame(lst)
#' slide2(x, y, sum, .size = 2)
#' slide2(lst, lst, ~ ., .size = 2)
#' slide2(df, df, ~ ., .size = 2)
#' pslide(lst, ~ ., .size = 1)
#' pslide(list(lst, lst), ~ ., .size = 2)
#'
#' ###
#' # row-wise sliding over data frame
#' ###
#'
#' my_df <- data.frame(
#'   group = rep(letters[1:2], each = 8),
#'   x = c(1:8, 8:1),
#'   y = 2 * c(1:8, 8:1) + rnorm(16),
#'   date = rep(as.Date("2016-06-01") + 0:7, 2)
#' )
#' 
#' slope <- function(...) {
#'   data <- list(...)
#'   fm <- lm(y ~ x, data = data)
#'   coef(fm)[[2]]
#' }
#' 
#' my_df %>% 
#'   nest(-group) %>% 
#'   mutate(slope = purrr::map(data, ~ pslide_dbl(., slope, .size = 2))) %>% 
#'   unnest()
slide2 <- function(
  .x, .y, .f, ..., .size = 1, .fill = NA, .partial = FALSE, 
  .align = "right", .bind = FALSE
) {
  if (.partial) {
    lst <- partial_pslider(
      .x, .y, .size = .size, .fill = .fill, .align = .align, .bind = .bind
    )
  } else {
    lst <- pslider(.x, .y, .size = .size, .bind = .bind)
  }
  out <- map2(lst[[1]], lst[[2]], .f = .f, ...)
  if (.partial) {
    out
  } else {
    pad_slide(out, .size, .fill, .align)
  }
}

#' @evalRd paste0('\\alias{slide2_', c("lgl", "chr", "int", "dbl"), '}')
#' @name slide2
#' @rdname slide2
#' @exportPattern ^slide2_
for(type in c("lgl", "chr", "int", "dbl")){
  assign(
    paste0("slide2_", type),
    replace_fn_names(slide2, list(map2 = paste0("map2_", type)))
  )
}

#' @rdname slide2
#' @export
slide2_dfr <- function(
  .x, .y, .f, ..., .size = 1, .fill = NA, .partial = FALSE, .align = "right",
  .bind = FALSE, .id = NULL
) {
  out <- slide2(
    .x, .y, .f = .f, ..., 
    .size = .size, .fill = .fill, .partial = .partial, 
    .align = .align, .bind = .bind
  )
  bind_df(out, .size, .fill, .id = .id)
}

#' @rdname slide2
#' @export
slide2_dfc <- function(
  .x, .y, .f, ..., .size = 1, .fill = NA, .partial = FALSE, 
  .align = "right", .bind = FALSE
) {
  out <- slide2(
    .x, .y, .f = .f, ..., 
    .size = .size, .fill = .fill, .partial = .partial, 
    .align = .align, .bind = .bind
  )
  bind_df(out, .size, .fill, byrow = FALSE)
}

#' @rdname slide2
#' @inheritParams purrr::pmap
#' @export
pslide <- function(
  .l, .f, ..., .size = 1, .fill = NA, .partial = FALSE, 
  .align = "right", .bind = FALSE
) {
  if (.partial) {
    lst <- partial_pslider(
      !!! .l, .size = .size, .fill = .fill, .align = .align, .bind = .bind
    )
  } else {
    lst <- pslider(!!! .l, .size = .size, .bind = .bind)
  }
  out <- pmap(lst, .f, ...)
  if (.partial) {
    out
  } else {
    pad_slide(out, .size, .fill, .align)
  }
}

#' @evalRd paste0('\\alias{pslide_', c("lgl", "chr", "int", "dbl"), '}')
#' @name pslide
#' @rdname slide2
#' @exportPattern ^pslide_
for(type in c("lgl", "chr", "int", "dbl")){
  assign(
    paste0("pslide_", type),
    replace_fn_names(pslide, list(pmap = paste0("pmap_", type)))
  )
}

#' @rdname slide2
#' @export
pslide_dfr <- function(
  .l, .f, ..., .size = 1, .fill = NA, .partial = FALSE, .align = "right",
  .bind = FALSE, .id = NULL
) {
  out <- pslide(
    .l, .f = .f, ..., 
    .size = .size, .fill = .fill, .partial = .partial, 
    .align = .align, .bind = .bind
  )
  bind_df(out, .size, .fill, .id = .id)
}

#' @rdname slide2
#' @export
#' @examples
#' ## window over 2 months
#' pedestrian %>% 
#'   filter(Sensor == "Southern Cross Station") %>% 
#'   index_by(yrmth = yearmonth(Date_Time)) %>% 
#'   nest(-yrmth) %>% 
#'   mutate(ma = slide_dbl(data, ~ mean(.$Count), .size = 2, .bind = TRUE))
#' # row-oriented workflow
#' \dontrun{
#' my_diag <- function(...) {
#'   data <- list(...)
#'   fit <- lm(Count ~ Time, data = data)
#'   tibble(fitted = fitted(fit), resid = residuals(fit))
#' }
#' pedestrian %>%
#'   filter_index("2015-01") %>%
#'   nest(-Sensor) %>%
#'   mutate(diag = purrr::map(data, ~ pslide_dfr(., my_diag, .size = 48)))
#' }
pslide_dfc <- function(
  .l, .f, ..., .size = 1, .fill = NA, .partial = FALSE, 
  .align = "right", .bind = FALSE
) {
  out <- pslide(
    .l, .f = .f, ..., 
    .size = .size, .fill = .fill, .partial = .partial, 
    .align = .align, .bind = .bind
  )
  bind_df(out, .size, .fill, byrow = FALSE)
}

#' Splits the input to a list according to the rolling window size.
#'
#' @param .x An objects to be split.
#' @param ... Multiple objects to be split in parallel.
#' @param .bind If `.x` is a list or data frame, the input will be flattened
#' to a list of data frames.
#' @inheritParams slide
#' @rdname slider
#' @seealso [partial_slider], [partial_pslider] for partial sliding
#' @export
#' @examples
#' x <- 1:5
#' y <- 6:10
#' z <- 11:15
#' lst <- list(x = x, y = y, z = z)
#' df <- as.data.frame(lst)
#'
#' slider(x, .size = 2)
#' slider(lst, .size = 2)
#' pslider(list(x, y), list(y))
#' slider(df, .size = 2)
#' pslider(df, df, .size = 2)
slider <- function(.x, .size = 1, .bind = FALSE) {
  .x <- check_slider_input(.x, .size = .size, .bind = .bind)
  len_x <- NROW(.x)
  abs_size <- abs(.size)
  if (abs_size > len_x) {
    abort(sprintf(slider_msg(), abs_size, len_x))
  }
  sign <- sign(.size)
  lst_idx <- seq_len(len_x - abs_size + 1)
  if (sign < 0) lst_idx <- rev(lst_idx) + 1
  out <- map(lst_idx, function(idx) .x[idx:(idx + sign * (abs_size - 1))])
  if (.bind) bind_lst(out) else out
}

#' @rdname slider
#' @export
pslider <- function(..., .size = 1, .bind = FALSE) { # parallel sliding
  lst <- recycle(list2(...))
  map(lst, function(x) slider(x, .size, .bind))
}

#' Partially splits the input to a list according to the rolling window size.
#'
#' @inheritParams slide
#' @rdname partial-slider
#' @export
#' @examples
#' x <- c(1, NA_integer_, 3:5)
#' slider(x, .size = 3)
#' partial_slider(x, .size = 3)
partial_slider <- function(.x, .size = 1, .fill = NA, .align = "right", 
  .bind = FALSE) {
  check_valid_window(.size, .align)
  .x <- check_slider_input(.x, .size = .size, .bind = .bind)
  len_x <- NROW(.x)
  abs_size <- abs(.size)
  if (abs_size > len_x) {
    abort(sprintf(slider_msg(), abs_size, len_x))
  }
  sign <- sign(.size)
  lst_idx <- seq_len(len_x) - sign * (abs_size - 1)
  if (sign < 0) lst_idx <- rev(lst_idx)
  out <- map(lst_idx, function(idx) {
    idx <- idx:(idx + sign * (abs_size - 1))
    size <- sum(idx <= 0 | idx > len_x) + 1
    pad_slide(.x[idx[idx > 0 & idx <= len_x]], size, .fill, .align, TRUE)
  })
  if (.bind) bind_lst(out) else out
}

#' @rdname partial-slider
#' @export
partial_pslider <- function(
  ..., .size = 1, .fill = NA, .align = "right", .bind = FALSE
) {
  lst <- recycle(list2(...))
  map(lst, function(x) partial_slider(x, .size, .fill, .align, .bind))
}

check_slider_input <- function(.x, .size = 1, .bind = FALSE) {
  bad_window_function(.size)
  abort_not_lst(.x, .bind = .bind)
  if (is.data.frame(.x)) .x <- as.list(.x)
  .x
}

bind_lst <- function(x) {
  type_elements <- flatten_chr(purrr::modify_depth(x, 2, ~ typeof(.)[1]))
  if (all(type_elements == "list")) {
    lapply(x, dplyr::bind_rows)
  } else {
    lapply(x, dplyr::combine)
  }
}

recycle <- function(x) {
  if (has_length(x, 0)) return(x)

  len <- map_int(x, length)
  max_len <- max(len)
  len1 <- len == 1
  check <- !len1 & len != max_len
  if (any(check)) {
    bad <- which(check)[1]
    abort(sprintf(
      "Element %s has length %s, not 1 or %s.", bad, len[bad], max_len
    ))
  }
  if (sum(len1) == 0) return(x)
  rep_idx <- which(len1)
  x[len1] <- lapply(x[rep_idx], rep, max_len)
  x
}

pad_slide <- function(
  x, .size = 1, .fill = NA, .align = "right", .partial = FALSE
) {
  .align <- match.arg(.align,
    c("right", "c", "center", "centre", "left",
      "cr", "center-right", "centre-right", 
      "cl", "center-left", "centre-left"
    )
  )
  if (is_false(.partial)) { # skip for `.partial = TRUE`
    check_valid_window(.size, .align)
  }
  if (is_null(.fill)) return(x) 
  fill_size <- abs(.size) - 1
  cl <- c("c", "center", "centre", "cl", "center-left", "centre-left")
  cr <- c("cr", "center-right", "centre-right")
  if (.partial && abs(.size) == 1) return(x)

  if (.align == "right") {
    c(rep(.fill, fill_size), x)
  } else if (.align %in% cl) {
    lsize <- floor(fill_size / 2)
    c(rep(.fill, lsize), x, rep(.fill, fill_size - lsize))
  } else if (.align %in% cr) {
    lsize <- ceiling(fill_size / 2)
    c(rep(.fill, lsize), x, rep(.fill, fill_size - lsize))
  } else {
    c(x, rep(.fill, fill_size)) # "left"
  }
}

bind_df <- function(x, .size, .fill = NA, .id = NULL, byrow = TRUE) {
  abs_size <- abs(.size)
  if (abs_size < 2) {
    if (byrow) {
      return(dplyr::bind_rows(x, .id = .id))
    } else {
      return(dplyr::bind_cols(x))
    }
  }
  lst <- new_list_along(x[[abs_size]])
  lst[] <- .fill
  if (byrow) {
    dplyr::bind_rows(lst, !!! x[-seq_len(abs_size - 1)], .id = .id)
  } else {
    dplyr::bind_cols(lst, !!! x[-seq_len(abs_size - 1)])
  }
}

slider_msg <- function() {
  "`abs(.size)` (%s) must not be larger than the length (%s) of the input."
}

#' Sliding window in parallel
#'
#' Multiprocessing equivalents of [slide()], [tile()], [stretch()] prefixed by `future_`.
#' * Variants for corresponding types: `future_*_lgl()`, `future_*_int()`, 
#' `future_*_dbl()`, `future_*_chr()`, `future_*_dfr()`, `future_*_dfc()`.
#' * Extra arguments `.progress` and `.options` for enabling progress bar and the 
#' future specific options to use with the workers. 
#'
#' @details 
#' It requires the package **furrr** to be installed. Please refer to [furrr](https://davisvaughan.github.io/furrr/) for performance and detailed usage.
#' @evalRd {suffix <- c("lgl", "chr", "int", "dbl", "dfr", "dfc"); c(paste0('\\alias{future_', c("slide", "slide2", "pslide"), '}'), paste0('\\alias{future_slide_', suffix, '}'), paste0('\\alias{future_slide2_', suffix, '}'), paste0('\\alias{future_pslide_', suffix, '}'))}
#' @name future_slide
#' @rdname future-slide
#' @exportPattern ^future_
#' @examples
#' if (!requireNamespace("furrr", quietly = TRUE)) {
#'   stop("Please install the furrr package to run these following examples.")
#' }
#' \dontrun{
#' library(furrr)
#' plan(multiprocess)
#' my_diag <- function(...) {
#'   data <- list(...)
#'   fit <- lm(Count ~ Time, data = data)
#'   tibble(fitted = fitted(fit), resid = residuals(fit))
#' }
#' pedestrian %>%
#'   nest(-Sensor) %>%
#'   mutate(diag = future_map(data, ~ future_pslide_dfr(., my_diag, .size = 48)))
#' }
# nocov start
assign("future_slide", replace_fn_names(slide, list(map = "future_map"), ns = "furrr"))
assign("future_slide2", replace_fn_names(slide2, list(map2 = "future_map2"), ns = "furrr"))
assign("future_pslide", replace_fn_names(pslide, list(pmap = "future_pmap"), ns = "furrr"))
assign("future_slide_dfr", replace_fn_names(slide_dfr, list(slide = "future_slide")))
assign("future_slide2_dfr", replace_fn_names(slide2_dfr, list(slide2 = "future_slide2")))
assign("future_pslide_dfr", replace_fn_names(pslide_dfr, list(pslide = "future_pslide")))
assign("future_slide_dfc", replace_fn_names(slide_dfc, list(slide = "future_slide")))
assign("future_slide2_dfc", replace_fn_names(slide2_dfc, list(slide2 = "future_slide2")))
assign("future_pslide_dfc", replace_fn_names(pslide_dfc, list(pslide = "future_pslide")))
for (type in c("lgl", "chr", "int", "dbl")) {
  assign(
    paste0("future_slide_", type),
    replace_fn_names(slide, list(map = paste0("future_map_", type)), ns = "furrr")
  )
  assign(
    paste0("future_slide2_", type),
    replace_fn_names(slide2, list(map2 = paste0("future_map2_", type)), ns = "furrr")
  )
  assign(
    paste0("future_pslide_", type),
    replace_fn_names(pslide, list(pmap = paste0("future_pmap_", type)), ns = "furrr")
  )
}
# nocov end
