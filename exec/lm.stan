functions {
/**
 * Increments the log-posterior with the logarithm of a multivariate normal 
 * likelihood with a scalar standard deviation for all errors
 * Equivalent to y ~ normal(intercept + X * beta, sigma) but faster
 * @param beta vector of coefficients (excluding intercept)
 * @param b precomputed vector of OLS coefficients (excluding intercept) 
 * @param middle matrix (excluding ones) typically precomputed as crossprod(X)
 * @param intercept scalar (assuming X is centered)
 * @param ybar precomputed sample mean of the outcome
 * @param SSR positive precomputed value of the sum of squared OLS residuals
 * @param sigma positive value for the standard deviation of the errors
 * @param N integer equal to the number of observations
 */
  void mvn_ols_lp(vector beta, vector b, matrix middle,
                  real intercept, real ybar,
                  real SSR, real sigma, int N) {
   increment_log_prob( -0.5 * (quad_form_sym(middle, beta - b) + 
                      N * square(intercept - ybar) + SSR) / 
                      square(sigma) - # 0.91... is log(sqrt(2 * pi()))
                      N * (log(sigma) + 0.91893853320467267) );
  }
}
data {
  int<lower=1> K;                     # number of predictors
  int<lower=0,upper=1> has_intercept; # 0 = no, 1 = yes
  int<lower=1> J;                     # number of groups
  // the rest of these are indexed by group but should work even if J = 1
  int<lower=1> N[J];                  # number of observations
  vector[K] xbar[J];                  # vector of means of the predictors
  vector<lower=0>[K] s_X[J];          # vector of standard deviations of the predictors
  matrix[K,K] XtX[J];                 # X'X where X is centered but not standardized
  real ybar[J];                       # sample mean of outcome
  real<lower=0> s_Y[J];               # standard deviation of the outcome
  vector[K] b[J];                     # OLS coefficients
  real<lower=0> SSR[J];               # OLS sum-of-squared residuals
  real<lower=0> eta;                  # shape hyperparameter
}
transformed data {
  real etaphalf;
  real half_K;
  etaphalf <- eta + 0.5;
  half_K <- 0.5 * K;
}
parameters { // must not call with init="0"
  row_vector[K] z_beta[J];         # primitives for coefficients
  real z_alpha[J * has_intercept]; # primitives for intercepts
  cholesky_factor_corr[K] L;       # L * L' is the hyperprior correlation matrix
  real<lower=0,upper=1> R2[J];     # proportions of variance explained
  vector<lower=0>[J] omega;        # overfitting factors
}
transformed parameters {
  real alpha[J * has_intercept];   # uncentered intercepts
  vector[K] beta[J];               # unstandardized coefficients
  real<lower=0> sigma[J];          # error standard deviations
  for (j in 1:J) {
    real Delta_y;                  # standard deviation of outcome for group j
    Delta_y <- s_Y[j] * omega[j];
    beta[j] <- transpose(mdivide_right_tri_low(z_beta[j], L)) *
               sqrt(R2[j] / dot_self(z_beta[j])) ./ s_X[j] * Delta_y;
    sigma[j] <- Delta_y * sqrt(1 - R2[j]);
    if (has_intercept == 1) {
      real se;
      se <- sigma[j] * sqrt(dot_self(mdivide_left_tri_low(L, xbar[j]) ./ s_X[j])
                            + 1.0 / N[j]);
      alpha[j] <- z_alpha[j] * se;
    }
  }
}
model {
  for (j in 1:J) {
    mvn_ols_lp(beta[j], b[j], XtX[j], 
               if_else(has_intercept, alpha[j], 0) + dot_product(xbar[j], beta[j]),
               ybar[j], SSR[j], sigma[j], N[j]); // likelihood contribution
    z_beta[j] ~ normal(0,1); // prior
  }                          // rest of the priors
  if (has_intercept == 1) z_alpha ~ normal(0,1);
  L ~ lkj_corr_cholesky(etaphalf);
  R2 ~ beta(half_K, eta);
  increment_log_prob(-log(omega)); # Jeffreys prior
}
