#' @importFrom rlang .data

#' Visualize original Forecast Intervals for the UK or European Forecast Hub Data Sets
#' @export

plot_quantiles <- function(df, model = NULL, location = NULL,
                           quantiles = c(0.05, 0.5, 0.95), base_size = 9) {
  l <- process_model_input(df, model)
  df <- l$df
  model <- l$model

  l <- process_location_input(df, location)
  df <- l$df
  location_name <- l$location_name

  df |>
    filter_quantiles(quantiles) |>
    mutate_horizon() |>
    change_to_date(forecast = TRUE, target_end = TRUE) |>
    ggplot2::ggplot(mapping = ggplot2::aes(x = .data$target_end_date)) +
    ggplot2::geom_line(
      mapping = ggplot2::aes(y = .data$prediction, color = factor(.data$quantile))
    ) +
    ggplot2::geom_line(mapping = ggplot2::aes(y = .data$true_value)) +
    ggplot2::scale_y_log10(labels = scales::label_number()) +
    ggplot2::facet_grid(
      rows = ggplot2::vars(.data$target_type),
      cols = ggplot2::vars(.data$horizon),
      scales = "free_y"
    ) +
    ggplot2::labs(
      title = stringr::str_glue("Predicted Quantiles in {location_name}"),
      subtitle = stringr::str_glue("model: {model}")
    ) +
    set_labels() +
    ggplot2::guides(color = ggplot2::guide_legend(nrow = 1)) +
    ggplot2::theme_light(base_size = base_size) +
    modify_theme()
}


#' Visualize updated Forecast Intervals for multiple Post-Processing Methods
#' @export

plot_intervals <- function(df, model = NULL, location = NULL,
                           target_type = c("Cases", "Deaths"),
                           quantile = 0.05, horizon = 1,
                           highlight_cv = TRUE, highlight_time_point = NULL,
                           base_size = 9) {
  target <- rlang::arg_match(arg = target_type, values = c("Cases", "Deaths"))
  h <- paste_horizon(horizon)

  l <- process_model_input(df, model)
  df <- l$df
  model <- l$model

  l <- process_location_input(df, location)
  df <- l$df
  location_name <- l$location_name

  p <- df |>
    process_quantile_pair(quantile) |>
    filter_target_types(target) |>
    filter_horizons(horizon) |>
    setup_intervals_plot() +
    ggplot2::labs(
      title = stringr::str_glue(
        "Predicted Incidences ({target} per 100k) in {location_name} {h}"
      ),
      subtitle = stringr::str_glue("model: {model}   |   quantile: {quantile}")
    ) +
    set_labels() +
    # making theme specifications before setting general theme does not work!
    ggplot2::theme_minimal(base_size = base_size) +
    modify_theme()

  if (highlight_cv) {
    p <- plot_training_end(p, df, type = "segment")
  }

  if (!is.null(highlight_time_point)) {
    p <- plot_vertical_line(p, df, highlight_time_point)
  }

  return(p)
}


#' Visualize updated Forecast Intervals along the `target_type` and `horizon` or
#' `quantile` dimensions
#' @export

plot_intervals_grid <- function(df, model = NULL, location = NULL,
                                facet_by = c("horizon", "quantile"),
                                quantiles = NULL, horizon = NULL,
                                highlight_cv = FALSE, base_size = 9) {
  facet_by <- rlang::arg_match(arg = facet_by, values = c("horizon", "quantile"))

  l <- process_model_input(df, model)
  df <- l$df
  model <- l$model

  l <- process_location_input(df, location)
  df <- l$df
  location_name <- l$location_name

  if (facet_by == "horizon") {
    if (is.null(quantiles)) {
      quantiles <- 0.05
    }

    q <- quantiles
    df <- facet_horizon(df, quantiles, horizon)
  } else if (facet_by == "quantile") {
    if (is.null(horizon)) {
      horizon <- 1
    }

    if (is.null(quantiles)) {
      quantiles <- c(0.01, 0.05, 0.1, 0.25)
    }

    h <- paste_horizon(horizon)
    df <- facet_quantile(df, quantiles, horizon)
  }

  p <- setup_intervals_plot(df)

  if (highlight_cv) {
    p <- plot_training_end(p, df, type = "vline")
  }

  if (facet_by == "horizon") {
    p <- p +
      ggplot2::facet_grid(
        rows = ggplot2::vars(.data$target_type),
        cols = ggplot2::vars(.data$horizon),
        scales = "free_y"
      ) +
      ggplot2::labs(
        title = stringr::str_glue(
          "Predicted Incidences (per 100k) in {location_name}"
        ),
        subtitle = stringr::str_glue("model: {model}   |   quantile: {q}")
      ) +
      set_labels() +
      ggplot2::theme_light(base_size = base_size) +
      modify_theme()
  } else if (facet_by == "quantile") {
    p <- p +
      ggplot2::facet_grid(
        rows = ggplot2::vars(.data$target_type),
        cols = ggplot2::vars(.data$quantile_group),
        scales = "free_y"
      ) +
      ggplot2::labs(
        title = stringr::str_glue(
          "Predicted Incidenced (per 100k) in {location_name} {h}"
        ),
        subtitle = stringr::str_glue("model: {model}")
      ) +
      set_labels() +
      ggplot2::theme_light(base_size = base_size) +
      modify_theme()
  }

  return(p)
}

#' Visualize the Output of `eval_methods()` as a Barplot or Heatmap
#' @export

plot_eval <- function(df_eval, heatmap = TRUE, base_size = 9) {
  if (ncol(df_eval) > 2 && !heatmap) {
    stop(paste(
      "Barplot is only available in one dimension",
      "(1 input to 'summarise_by' and single evaluation method)"
    ))
  }

  title <- get_plot_title(df_eval)

  summarise_by <- attr(df_eval, which = "summarise_by")
  xlabel <- get_xlabel(summarise_by)
  first_colname <- summarise_by[1]

  # for limits of color palette
  max_value <- get_max_value(df_eval)

  # keep y-axis order the same as in input dataframe
  df_eval[[1]] <- factor(df_eval[[1]], levels = df_eval[[1]])

  if (!heatmap) {
    return(plot_bars(df_eval, title, first_colname, max_value, base_size))
  }

  # this part belongs to heatmap plot
  df_plot <- df_eval |>
    tidyr::pivot_longer(
      cols = -1, names_to = "colnames", values_to = "values"
    )

  # keep x-axis order the same as in input dataframe
  x_order <- colnames(df_eval)[-1]
  df_plot$colnames <- factor(df_plot$colnames, levels = x_order)

  # when there are no categories on x-axis, do not display any name
  if (dplyr::n_distinct(df_plot[[2]]) == 1) {
    df_plot[[2]] <- ""
  }

  plot_heatmap(df_plot, title, first_colname, max_value, xlabel, base_size)
}
