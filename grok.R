# R script to recreate Figure 3 from Johnson et al. (2015)
# Plots relative width of 95% HPD intervals for R0 components and dR0/dT

# Load required packages
library(rjags)
library(coda)
library(HDInterval)
library(readxl)
library(dplyr)
library(ggplot2)
library(reshape2)

# Set seed for reproducibility
set.seed(123)

# Load and preprocess data
# EIP data from the_one_we_need.xlsx
eip_data <- read_excel("data/the_one_we_need.xlsx")
eip_data_gambiae <- eip_data %>%
  filter(Interactor1Species == "gambiae", SecondStressorValue == 0) %>%
  select(T = Interactor1Temp, EIP = OriginalTraitValue)
eip_data_gambiae$PDR <- 1 / eip_data_gambiae$EIP

# Oocyst prevalence data from the_one_we_need_2.csv
prev_data <- read.csv("data/the_one_we_need_2.csv")
prev_data_gambiae <- prev_data %>%
  filter(SecondStressorValue == 0, Interactor1Species == "gambiae") %>%
  group_by(T = Interactor1Temp) %>%
  summarise(
    success = sum(OriginalTraitValue * Interactor1Number, na.rm = TRUE) / 100,
    total = sum(Interactor1Number, na.rm = TRUE)
  ) %>%
  filter(total > 0)

# Placeholder data for other components (replace with actual data if available)
temps <- seq(15, 35, by = 5)
data_a <- data.frame(T = temps, value = c(0.1, 0.3, 0.5, 0.4, 0.2))  # Bite rate
data_efd <- data.frame(T = temps, value = c(20, 50, 80, 60, 30))  # Fecundity
data_pea <- data.frame(T = temps, value = c(0.2, 0.5, 0.8, 0.6, 0.3))  # Egg-to-adult survival
data_mdr <- data.frame(T = temps, value = c(0.05, 0.1, 0.15, 0.12, 0.08))  # Mosquito development rate
data_mu <- data.frame(T = temps, value = c(0.1, 0.08, 0.07, 0.09, 0.12))  # Mortality

# Define JAGS model
jags_model <- "
model {
  # Bite rate (a) - Brière function
  for (i in 1:N_a) {
    a_obs[i] ~ dnorm(a_mean[i], a_tau) T(0, )
    a_mean[i] <- ifelse(T_a[i] > a_T0 && T_a[i] < a_Tm && a_Tm - T_a[i] > 0,
                        a_c * T_a[i] * (T_a[i] - a_T0) * sqrt(a_Tm - T_a[i]),
                        0)
  }
  a_T0 ~ dunif(0, 24)
  a_Tm <- 25 + a_tm
  a_tm ~ dgamma(8.45, 0.65) T(10, 20)  # Ensure a_Tm > 35
  a_c ~ dexp(200)
  a_tau ~ dgamma(1, 1)

  # Vector competence (bc) - Quadratic function
  for (i in 1:N_bc) {
    bc_obs[i] ~ dbin(bc_p[i], bc_total[i])
    bc_p[i] <- ifelse(T_bc[i] > bc_T0 && T_bc[i] < bc_Tm,
                      min(1, -bc_a * (T_bc[i] - bc_T0) * (T_bc[i] - bc_Tm)),
                      0)
  }
  bc_T0 ~ dgamma(128, 8)
  bc_Tm <- 30 + bc_tm
  bc_tm ~ dgamma(42.25, 3.25)
  bc_a ~ dexp(100)
  bc_tau ~ dgamma(1, 1)

  # Fecundity (EFD) - Quadratic (concave down)
  for (i in 1:N_efd) {
    efd_obs[i] ~ dnorm(efd_mean[i], efd_tau) T(0, )
    efd_mean[i] <- ifelse(T_efd[i] > efd_T0 && T_efd[i] < efd_Tm,
                          -efd_a * (T_efd[i] - efd_T0) * (T_efd[i] - efd_Tm),
                          0)
  }
  efd_T0 ~ dnorm(17, 3^2)
  efd_Tm ~ dnorm(33, 3^2)
  efd_a ~ dgamma(4, 13)
  efd_tau ~ dgamma(1, 1)

  # Egg-to-adult survival (p_EA) - Quadratic (concave down)
  for (i in 1:N_pea) {
    pea_obs[i] ~ dnorm(pea_mean[i], pea_tau) T(0, 1)
    pea_mean[i] <- ifelse(T_pea[i] > pea_T0 && T_pea[i] < pea_Tm,
                          min(1, -pea_a * (T_pea[i] - pea_T0) * (T_pea[i] - pea_Tm)),
                          0)
  }
  pea_T0 ~ dnorm(12, 5^2) T(0, 24)
  pea_Tm ~ dnorm(36, 3^2) T(25, 45)
  pea_a ~ dexp(100)
  pea_tau ~ dgamma(1, 1)

  # Mosquito development rate (MDR) - Brière function
  for (i in 1:N_mdr) {
    mdr_obs[i] ~ dnorm(mdr_mean[i], mdr_tau) T(0, )
    mdr_mean[i] <- ifelse(T_mdr[i] > mdr_T0 && T_mdr[i] < mdr_Tm,
                          mdr_c * T_mdr[i] * (T_mdr[i] - mdr_T0) * sqrt(mdr_Tm - T_mdr[i]),
                          0)
  }
  mdr_T0 ~ dnorm(15, 9^2) T(0, 24)
  mdr_Tm ~ dnorm(37, 2^2) T(25, 45)
  mdr_c ~ dexp(1000)
  mdr_tau ~ dgamma(1, 1)

  # Mortality (mu) - Quadratic (concave up)
  for (i in 1:N_mu) {
    mu_obs[i] ~ dnorm(mu_mean[i], mu_tau) T(0, )
    mu_mean[i] <- ifelse(mu_a * T_mu[i]^2 - mu_b * T_mu[i] + mu_c > 0,
                         mu_a * T_mu[i]^2 - mu_b * T_mu[i] + mu_c,
                         0.0001)
  }
  mu_a ~ dnorm(2.3, 0.3^2)
  mu_b ~ dnorm(0.21, 0.02^2)
  mu_c ~ dgamma(2, 2)
  mu_tau ~ dgamma(1, 1)

  # Parasite development rate (PDR) - Brière function
  for (i in 1:N_pdr) {
    pdr_obs[i] ~ dnorm(pdr_mean[i], pdr_tau) T(0, )
    pdr_mean[i] <- ifelse(T_pdr[i] > pdr_T0 && T_pdr[i] < pdr_Tm && pdr_Tm - T_pdr[i] > 0,
                          pdr_c * T_pdr[i] * (T_pdr[i] - pdr_T0) * sqrt(pdr_Tm - T_pdr[i]),
                          0.0001)
  }
  pdr_T0 ~ dnorm(14, 3.5^2)
  pdr_Tm <- 31 + pdr_tm
  pdr_tm ~ dgamma(30, 3) T(9, )  # Ensure pdr_Tm > 40
  pdr_c ~ dexp(100)
  pdr_tau ~ dgamma(1, 1)

  # Calculate components and R0 across temperature range
  for (t in 1:N_temp) {
    a_t[t] <- ifelse(temp[t] > a_T0 && temp[t] < a_Tm && a_Tm - temp[t] > 0,
                     a_c * temp[t] * (temp[t] - a_T0) * sqrt(a_Tm - temp[t]),
                     0)
    bc_t[t] <- ifelse(temp[t] > bc_T0 && temp[t] < bc_Tm,
                      min(1, -bc_a * (temp[t] - bc_T0) * (temp[t] - bc_Tm)),
                      0)
    efd_t[t] <- ifelse(temp[t] > efd_T0 && temp[t] < efd_Tm,
                       -efd_a * (temp[t] - efd_T0) * (temp[t] - efd_Tm),
                       0)
    pea_t[t] <- ifelse(temp[t] > pea_T0 && temp[t] < pea_Tm,
                       min(1, -pea_a * (temp[t] - pea_T0) * (temp[t] - pea_Tm)),
                       0)
    mdr_t[t] <- ifelse(temp[t] > mdr_T0 && temp[t] < mdr_Tm,
                       mdr_c * temp[t] * (temp[t] - mdr_T0) * sqrt(mdr_Tm - temp[t]),
                       0)
    mu_t[t] <- ifelse(mu_a * temp[t]^2 - mu_b * temp[t] + mu_c > 0,
                      mu_a * temp[t]^2 - mu_b * temp[t] + mu_c,
                      0.0001)
    pdr_t[t] <- ifelse(temp[t] > pdr_T0 && temp[t] < pdr_Tm && pdr_Tm - temp[t] > 0,
                       pdr_c * temp[t] * (temp[t] - pdr_T0) * sqrt(pdr_Tm - temp[t]),
                       0.0001)
    M_t[t] <- ifelse((efd_t[t] * pea_t[t] * mdr_t[t]) > 0 && (mu_t[t]^2) > 0,
                     (efd_t[t] * pea_t[t] * mdr_t[t]) / (mu_t[t]^2),
                     0.0001)
    R0_t[t] <- ifelse(M_t[t] > 0 && mu_t[t] > 0 && pdr_t[t] > 0,
                      sqrt((M_t[t] / (N * r)) * (a_t[t]^2 * bc_t[t] * exp(-mu_t[t] / pdr_t[t])) / mu_t[t]),
                      0)
  }
}
"

# Prepare data for JAGS
jags_data <- list(
  T_a = data_a$T,
  a_obs = data_a$value,
  N_a = nrow(data_a),
  T_bc = prev_data_gambiae$T,
  bc_obs = round(prev_data_gambiae$success),
  bc_total = prev_data_gambiae$total,
  N_bc = nrow(prev_data_gambiae),
  T_efd = data_efd$T,
  efd_obs = data_efd$value,
  N_efd = nrow(data_efd),
  T_pea = data_pea$T,
  pea_obs = data_pea$value,
  N_pea = nrow(data_pea),
  T_mdr = data_mdr$T,
  mdr_obs = data_mdr$value,
  N_mdr = nrow(data_mdr),
  T_mu = data_mu$T,
  mu_obs = data_mu$value,
  N_mu = nrow(data_mu),
  T_pdr = eip_data_gambiae$T,
  pdr_obs = eip_data_gambiae$PDR,
  N_pdr = nrow(eip_data_gambiae),
  temp = seq(10, 35, by = 0.1),
  N_temp = length(seq(10, 35, by = 0.1)),
  N = 1000,  # Human density (assumed)
  r = 0.1    # Human recovery rate (assumed)
)

# Initial values
inits <- list(
  list(a_T0 = 10, a_tm = 12, a_c = 0.005, a_tau = 1,
       bc_T0 = 15, bc_tm = 5, bc_a = 0.01, bc_tau = 1,
       efd_T0 = 17, efd_Tm = 33, efd_a = 0.3, efd_tau = 1,
       pea_T0 = 12, pea_Tm = 36, pea_a = 0.01, pea_tau = 1,
       mdr_T0 = 15, mdr_Tm = 37, mdr_c = 0.001, mdr_tau = 1,
       mu_a = 2.3, mu_b = 0.21, mu_c = 1, mu_tau = 1,
       pdr_T0 = 14, pdr_tm = 10, pdr_c = 0.01, pdr_tau = 1),
  list(a_T0 = 12, a_tm = 14, a_c = 0.006, a_tau = 1,
       bc_T0 = 16, bc_tm = 6, bc_a = 0.015, bc_tau = 1,
       efd_T0 = 18, efd_Tm = 34, efd_a = 0.4, efd_tau = 1,
       pea_T0 = 13, pea_Tm = 37, pea_a = 0.015, pea_tau = 1,
       mdr_T0 = 16, mdr_Tm = 38, mdr_c = 0.002, mdr_tau = 1,
       mu_a = 2.4, mu_b = 0.22, mu_c = 1.5, mu_tau = 1,
       pdr_T0 = 15, pdr_tm = 11, pdr_c = 0.015, pdr_tau = 1),
  list(a_T0 = 11, a_tm = 11, a_c = 0.004, a_tau = 1,
       bc_T0 = 14, bc_tm = 4, bc_a = 0.008, bc_tau = 1,
       efd_T0 = 16, efd_Tm = 32, efd_a = 0.2, efd_tau = 1,
       pea_T0 = 11, pea_Tm = 35, pea_a = 0.008, pea_tau = 1,
       mdr_T0 = 14, mdr_Tm = 36, mdr_c = 0.0005, mdr_tau = 1,
       mu_a = 2.2, mu_b = 0.20, mu_c = 0.5, mu_tau = 1,
       pdr_T0 = 13, pdr_tm = 9, pdr_c = 0.008, pdr_tau = 1),
  list(a_T0 = 13, a_tm = 15, a_c = 0.007, a_tau = 1,
       bc_T0 = 17, bc_tm = 7, bc_a = 0.02, bc_tau = 1,
       efd_T0 = 19, efd_Tm = 35, efd_a = 0.5, efd_tau = 1,
       pea_T0 = 14, pea_Tm = 38, pea_a = 0.02, pea_tau = 1,
       mdr_T0 = 17, mdr_Tm = 39, mdr_c = 0.003, mdr_tau = 1,
       mu_a = 2.5, mu_b = 0.23, mu_c = 2, mu_tau = 1,
       pdr_T0 = 16, pdr_tm = 12, pdr_c = 0.02, pdr_tau = 1),
  list(a_T0 = 9, a_tm = 10, a_c = 0.003, a_tau = 1,
       bc_T0 = 13, bc_tm = 3, bc_a = 0.005, bc_tau = 1,
       efd_T0 = 15, efd_Tm = 31, efd_a = 0.1, efd_tau = 1,
       pea_T0 = 10, pea_Tm = 34, pea_a = 0.005, pea_tau = 1,
       mdr_T0 = 13, mdr_Tm = 35, mdr_c = 0.0003, mdr_tau = 1,
       mu_a = 2.1, mu_b = 0.19, mu_c = 0.3, mu_tau = 1,
       pdr_T0 = 12, pdr_tm = 10, pdr_c = 0.005, pdr_tau = 1)
)

# Initialize JAGS model
jags <- jags.model(textConnection(jags_model), data = jags_data, n.chains = 5, inits = inits)

# Burn-in
update(jags, 5000)

# Sample from posterior
samples <- coda.samples(jags, c("a_t", "bc_t", "efd_t", "pea_t", "mdr_t", "mu_t", "pdr_t", "R0_t"), n.iter = 5000)

# Thin samples
samples_thinned <- window(samples, thin = 5)

# Extract samples for components
temps <- seq(10, 35, by = 0.1)
n_temps <- length(temps)

# Extract component samples
a_samples <- do.call(rbind, samples_thinned)[, grep("a_t", colnames(do.call(rbind, samples_thinned)))]
bc_samples <- do.call(rbind, samples_thinned)[, grep("bc_t", colnames(do.call(rbind, samples_thinned)))]
efd_samples <- do.call(rbind, samples_thinned)[, grep("efd_t", colnames(do.call(rbind, samples_thinned)))]
pea_samples <- do.call(rbind, samples_thinned)[, grep("pea_t", colnames(do.call(rbind, samples_thinned)))]
mdr_samples <- do.call(rbind, samples_thinned)[, grep("mdr_t", colnames(do.call(rbind, samples_thinned)))]
mu_samples <- do.call(rbind, samples_thinned)[, grep("mu_t", colnames(do.call(rbind, samples_thinned)))]
pdr_samples <- do.call(rbind, samples_thinned)[, grep("pdr_t", colnames(do.call(rbind, samples_thinned)))]
R0_samples <- do.call(rbind, samples_thinned)[, grep("R0_t", colnames(do.call(rbind, samples_thinned)))]

# Compute 95% HPD intervals and means for components
compute_hpd <- function(samples) {
  hpd <- apply(samples, 2, function(x) hdi(x, credMass = 0.95))
  means <- apply(samples, 2, mean, na.rm = TRUE)
  list(hpd = hpd, means = means, width = hpd[2,] - hpd[1,])
}

a_stats <- compute_hpd(a_samples)
bc_stats <- compute_hpd(bc_samples)
efd_stats <- compute_hpd(efd_samples)
pea_stats <- compute_hpd(pea_samples)
mdr_stats <- compute_hpd(mdr_samples)
mu_stats <- compute_hpd(mu_samples)
pdr_stats <- compute_hpd(pdr_samples)
R0_stats <- compute_hpd(R0_samples)

# Compute relative widths (width / mean)
rel_width_a <- a_stats$width / (a_stats$means + 1e-6)
rel_width_bc <- bc_stats$width / (bc_stats$means + 1e-6)
rel_width_efd <- efd_stats$width / (efd_stats$means + 1e-6)
rel_width_pea <- pea_stats$width / (pea_stats$means + 1e-6)
rel_width_mdr <- mdr_stats$width / (mdr_stats$means + 1e-6)
rel_width_mu <- mu_stats$width / (mu_stats$means + 1e-6)
rel_width_pdr <- pdr_stats$width / (pdr_stats$means + 1e-6)

# Data frame for Figure 3a
df_fig3a <- data.frame(
  Temperature = rep(temps, 7),
  Relative_Width = c(rel_width_a, rel_width_bc, rel_width_efd, rel_width_pea, rel_width_mdr, rel_width_mu, rel_width_pdr),
  Component = rep(c("a", "bc", "EFD", "p_EA", "MDR", "μ", "PDR"), each = n_temps)
)

# Compute dR0/dT using numerical derivatives
dR0_dT_samples <- matrix(NA, nrow = nrow(R0_samples), ncol = n_temps)
for (i in 1:nrow(R0_samples)) {
  R0 <- R0_samples[i,]
  dR0_dT <- numeric(n_temps)
  for (t in 2:(n_temps-1)) {
    dR0_dT[t] <- (R0[t+1] - R0[t-1]) / (temps[t+1] - temps[t-1])
  }
  dR0_dT[1] <- dR0_dT[2]  # Forward difference at boundary
  dR0_dT[n_temps] <- dR0_dT[n_temps-1]  # Backward difference at boundary
  dR0_dT_samples[i,] <- dR0_dT
}

# Compute 95% HPD for dR0/dT
dR0_dT_stats <- compute_hpd(dR0_dT_samples)
rel_width_dR0_dT <- dR0_dT_stats$width / (dR0_dT_stats$means + 1e-6)

# Data frame for Figure 3b
df_fig3b <- data.frame(
  Temperature = temps,
  Relative_Width = rel_width_dR0_dT
)

# Plot Figure 3a
p1 <- ggplot(df_fig3a, aes(x = Temperature, y = Relative_Width, color = Component)) +
  geom_line(size = 1) +
  scale_color_manual(values = c("a" = "black", "bc" = "cyan", "EFD" = "red", "p_EA" = "blue",
                                "MDR" = "magenta", "μ" = "green", "PDR" = "yellow")) +
  labs(x = "Temperature (°C)", y = "Relative width of 95% HPD intervals",
       title = "a") +
  theme_minimal() +
  theme(legend.position = "top", legend.title = element_blank())

# Plot Figure 3b
p2 <- ggplot(df_fig3b, aes(x = Temperature, y = Relative_Width)) +
  geom_line(size = 1, color = "black") +
  labs(x = "Temperature (°C)", y = "Relative width of 95% HPD in (dR₀/dT)",
       title = "b") +
  theme_minimal()

# Combine plots
library(gridExtra)
png("Figure3.png", width = 800, height = 400)
grid.arrange(p1, p2, ncol = 2)
dev.off()
