
#'@title CAUSE
#'@description Fit CAUSE sharing and causal models,
#'calculate ELPD test statistic and estimate posteriors
#'@param X An object of class cause_data containing data for the two traits.
#'@param param_ests Object of class cause_params output by est_cause_params.
#'This contains estimates of the mixing proportions and an estimate of rho,
#'the correlation in test statistics that is due to overlapping samples or population structure.
#'@param variants A vector of variants to include in the analysis.
#'@param sigma_g Parameter specifying the prior distribution of gamma and eta.
#'gamma ~ N(0, sigma_g), eta ~ N(0, sigma_g).
#'@param qalpha,qbeta Parameters defining the prior distribution of q.
#'q ~ Beta(qalpha, qbeta)
#'@param max_q Largest value of q to be allowed. If max_q < 1 then the prior will be truncated.
#'@param force If true, do not give an error if parameter estimates did not converge.
#'@param n_start_gamma_eta,n_start_q Number of starting bins for grid approximation.
#'You shouldn't need to change these but if you are suspicious about your results, you might try increasing them.
#'It's best to use odd numbers.
#'@return An object of class "cause" that contains posterior estimates for causal and sharing models as well as
#'results of the model comparison test. See Details.
#'@details This function estimates posterior distributions for gamma, eta, and q under the sharing and causal models
#'and computes a test statistic comparing the two models. The returned object contains
#'
#'sharing, causal: posterior estimates under model.
#'
#'elpd: A data frame giving estimated difference in elpd between pairs of sharing, causal and null model with standard errors.
#'The null model is the model with gamma = eta = q = 0 and allows neither a causal effect nor correlated pleiotropy.
#'
#'data: The data used to compute the object. This data frame also contains posterior estimates for each variant of acting
#'through U under both models.
#'
#'sigma_g: Prior variance of gamma and eta. This value is chosen based on the data by default but can be supplied using the
#'sigma_g parameter in the function call.
#'
#'qalpha, qbeta: The prior distribution of q is Beta(qalpha, qbeta)
#'
#'Functions summary() and plot() can be used with cause objects. See ?summary.cause and ?plot.cause
#'@export
cause <- function(X, param_ests, variants = X$snp,
                  sigma_g, qalpha = 1, qbeta=10,
                  max_q = 1, force=FALSE,
                  n_start_gamma_eta = 21, n_start_q = 11){
  if(!inherits(X, "cause_data")){
    X <- new_cause_data(X)
  }
  stopifnot(inherits(param_ests, "cause_params"))
  if(!param_ests$converged){
    if(!force){
      stop("The parameter estimates you are using did not converge.
           If you are sure you want to use them anyway, rerun with force=TRUE\n")
    }else{
      warning("Parameter estimates are not converged but we are going forward anyway.\n")
    }
  }
  if(!all(variants %in% X$snp)){
    stop("Not all `variants` are in data.", call.=FALSE)
  }
  X <- filter(X, snp %in% variants)
  X <- new_cause_data(X)
  cat("Estimating CAUSE posteriors using ", nrow(X), " variants.\n")
  stopifnot(inherits(param_ests, "cause_params"))

  m <- pbeta(max_q, qalpha, qbeta)
  qprior <- function(q){
    ret <- rep(0, length(q))
    ret[q > 0 & q < max_q] <- dbeta(q[q > 0 & q < max_q], qalpha, qbeta)/m
    return(ret)
  }

  if(missing(sigma_g)){
    sigma_g <- eta_gamma_prior(X)
  }

  fit2 <- cause_grid_adapt(X, param_ests,
                           max_post_per_bin = 0.001,
                           params = c("eta", "q"),
                           priors = list(function(b){dnorm(b, 0, sigma_g)},
                                         qprior),
                           n_start = c(n_start_gamma_eta, n_start_q))
  fit3 <- cause_grid_adapt(X, param_ests,
                               max_post_per_bin = 0.001,
                               params = c("gamma", "eta", "q"),
                               priors = list(function(b){dnorm(b, 0, sigma_g)},
                                             function(b){dnorm(b, 0, sigma_g)},
                                             qprior),
                               n_start = c(n_start_gamma_eta, n_start_gamma_eta, n_start_q))
  fit0 <- structure(list("joint_post"=NULL, rho = param_ests$rho, mix_grid=param_ests$mix_grid), class="cause_post")
  fits <- list("null"=fit0, "sharing"=fit2, "causal" = fit3)
  elpd <- in_sample_elpd_loo(X, fits)

  X$delta_elpd <- with(elpd, loos[[2]]$pointwise[,1] - loos[[3]]$pointwise[,1])

  X$prob_Z1_sharing <- Z_post(X, fit2)
  X$prob_Z1_causal <- Z_post(X, fit3)
  class(X) <- c("cause_data_fit", "cause_data", "data.frame")

  res <- list("sharing"=fit2, "causal" = fit3, elpd=elpd$mods, "loos" = elpd$loos, "data"=X,
              "sigma_g" = sigma_g, "qalpha" = qalpha, "qbeta" = qbeta)
  class(res) <- "cause"
  return(res)
}

#'@title Create a new cause_data_fit object
#'@param x a data.frame that includes columns snp, beta_hat_1, seb1, beta_hat_2, seb2, delta_elpd,
#'prob_Z1_sharing, prob_Z1_causal in any order.
#'x may also contain other columns
#'@return and object of class cause_data and data.frame.
#'@export
new_cause_data_fit <- function(x = data.frame()){
  stopifnot(inherits(x, "data.frame"))
  stopifnot(all(c("snp", "beta_hat_1", "seb1", "beta_hat_2", "seb2",
                  "delta_elpd", "prob_Z1_sharing", "prob_Z1_causal") %in% names(x)))
  structure(x, class = c("cause_data_fit", "cause_data", "data.frame"))
}
