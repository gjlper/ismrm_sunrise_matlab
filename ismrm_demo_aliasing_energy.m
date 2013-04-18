%%
%Clean up
close all;
clear all

acc_factor = 4;
cal_noise_scale = 0.1;
accel_noise_scale = 0.05;

%%
%Load Image & Sensitivity Maps
load im1.mat
load smaps_phantom.mat
load noise_covariances.mat
%smaps = smaps(:,:,1:2:end);
%im1 = im1.';

ncoils = size(smaps,3);
Rn = eye(ncoils);
imsize = size(im1);
nx = imsize(1);
ny = imsize(2);

pixel_mask = sum(abs(smaps),3) > 0;

%%
% Create Calibration Data
cal_shape = [64 20];
channel_im = smaps .* repmat(im1, [1 1 ncoils]);
cal_data = ismrm_transform_image_to_kspace(channel_im, [1 2], cal_shape);
noise = cal_noise_scale * max(im1(:)) * ismrm_generate_correlated_noise(cal_shape, Rn);
cal_data = cal_data + noise;

f = hamming(cal_shape(1)) * hamming(cal_shape(2))';
fmask = repmat(f, [1 1 ncoils]);
filtered_cal_data = cal_data .* fmask;

cal_im = ismrm_transform_kspace_to_image(filtered_cal_data, [1 2], imsize);
cal_im = cal_im .* repmat(pixel_mask, [1 1 ncoils]);

csm_est = ismrm_estimate_csm_mckenzie(cal_im);
csm_est = ismrm_normalize_shading_to_sos(csm_est);


%%
% Calibrate

csm = smaps;
csm = ismrm_normalize_shading_to_sos(csm);

kernel_shape = [5 7];
jer_lookup_dd = ismrm_compute_jer_data_driven(cal_data, kernel_shape);
ccm = ismrm_compute_ccm(csm, Rn);

num_recons = 1;
unmix = zeros([imsize ncoils num_recons]);
%unmix(:,:,:,1) = ismrm_calculate_sense_unmixing(acc_factor, csm_est, Rn) .* acc_factor;
[unmix(:,:,:,1), gmt] = ismrm_calculate_sense_unmixing(acc_factor, csm, Rn);
unmix(:,:,:,1) = unmix(:,:,:,1) .* acc_factor;
%unmix(:,:,:,3) = ismrm_calculate_jer_unmixing(jer_lookup_dd, acc_factor, ccm, 0, true);
%unmix(:,:,:,1) = ismrm_calculate_jer_unmixing(jer_lookup_dd, acc_factor, ccm, 0.01, true);

%%
% Create Accelerated Data
noise = accel_noise_scale * max(im1(:)) * ismrm_generate_correlated_noise(imsize, Rn);
data = ismrm_transform_image_to_kspace(channel_im, [1 2]) + noise;
sp = ismrm_generate_sampling_pattern(size(im1), acc_factor, 0);
data_accel = data .* repmat(sp == 1 | sp == 3,[1 1 ncoils]);
im_alias = ismrm_transform_kspace_to_image(data_accel,[1,2]);% ./ acc_factor;

im_full = ismrm_transform_kspace_to_image(data, [1, 2]);

%ccm_true = ismrm_compute_ccm(smaps, Rn);
im_full = abs(sum(im_full .* ccm, 3));

%%
% Analyze Reconstruction Candidates

aem = zeros([imsize num_recons]);
gmap = zeros([imsize, num_recons+1]);
im_hat = zeros([imsize, num_recons]);
im_diff = zeros([imsize, num_recons]);

gmap(:,:,2) = gmt;
optimal_ccm = ismrm_compute_ccm(csm, Rn);
signal_mask = imclose(im1>100.0, strel('disk', 5)); ismrm_imshow(signal_mask, [0 1]);


for recon_index = 1:num_recons,
    aem(:,:,recon_index) = ismrm_calculate_aem(signal_mask, csm, unmix(:,:,:,recon_index), acc_factor);
    gmap(:,:,recon_index) = ismrm_calculate_gmap(unmix(:,:,:,recon_index), optimal_ccm, Rn, acc_factor);
    im_hat(:,:,recon_index) = abs(sum(im_alias .* unmix(:,:,:,recon_index), 3));
    im_diff(:,:,recon_index) = abs(im_hat(:,:,recon_index) - im_full);
end
    


ismrm_imshow(aem, [0 0.1]); colormap(jet);
ismrm_imshow(gmap); colormap(jet); colorbar;
ismrm_imshow(im_hat);
ismrm_imshow(im_diff);
ismrm_imshow(im_full);