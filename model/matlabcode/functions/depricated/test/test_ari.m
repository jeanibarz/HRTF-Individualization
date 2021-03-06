function test_ari(db)

% Load HRIRs
[hrirs,subject_ids,a,angles,b,hrir_db_length,c,d,e,f,fs,exp_sub] = db_import(db);

pc_order = size(hrirs,4);sh_order = 4;


freq_mode = 2;%1=lin,2 = log;
pca_mode = 1;
pca_struktur = 2;
pca_mean = 2;
ear_mode = 2;
ears = ':';

% May be it makes sense to use directly the Minimum Phase HRIRs here
% instead of the normal HRIRs, I have not tried it
eaz = unique(angles(:,1));
idx = find(angles(:,1) == eaz(6));
subj = 1:size(hrirs,1);
ang = 1:size(hrirs,2);


% DTF = 20*log10(hrirs);DTF=DTF(:,:,:,1:256);

[org_spc,pca_mean] = pca_in2(hrirs,subj,ang,ears,pca_mode,pca_struktur,pca_mean,freq_mode,ear_mode,[],[],fs);

[pcs,pc_weights,latent] = princomp(org_spc,'econ'); % both ears

% mean_pca = reshape(mean(org_spc),256,2)';
% mean_pca = repmat(reshape(mean_pca,[1 1 2 256]),[50 187 1 1]);

pca_inv_reshape(org_spc,hrirs,pca_struktur,ears);

org_spc = permute(reshape(org_spc,[size(hrirs,1) length(idx) size(hrirs,4) size(hrirs,3)]),[1 2 4 3]) + pca_mean; % org_spc = org_spc + repmat(pca_mean,[1 size(org_spc,2) 1 1]);

pc_weights = reshape(pc_weights,[size(hrirs,1),size(hrirs,2),size(hrirs,4)]);

max_sh_order = 9;
max_pc = 6;

for sho = 1:max_sh_order
    disp(sprintf('Entering Order %d',sho-1));
    max_id = 1:((sho-1+1)^2);
    sha = [];
    for a = 1:size(angles,1)        
        % Evaluate Spherical Harmonic Basis
        sha(:,a) = SHCreateYVec(sho-1,angles(a,1),90-angles(a,2),'deg'); % Convert Elevation to Zenith (Inclination or Colatitude)
%         sha(:,a) = sh_matrix_real(sho,angles(a,1)/180*pi,90-angles(a,2)/180*pi); % Convert Elevation to Zenith (Inclination or Collatidude)    
    end 
%   Estimate Matrix Condition for Inverting
    cnd(sho) = cond(sha,2);
%     sha_inv = (sha*sha')\sha;
    sha_inv = pinv(sha*sha'); %(sha*sha')\sha;
    for u = 1:size(pc_weights,1)
        % Obtain SH weights for the order under consideration
        sh_weights(u,:,:) = sha_inv*squeeze(pc_weights(u,:,:)); 
        % Reconstruct PC Weights
        pc_weights_rc(sho,u,:,:) = sha*squeeze(sh_weights(u,:,:));
        % Estimate Shape RMS Error
        for pc = 1:max_pc
            % Transform to Cartesian Coordinates and calculate the RMS
            % error for the Different Points in the Shape 
            [co(u,pc,:,1),co(u,pc,:,2),co(u,pc,:,3)] = sph2cart(angles(:,1)/180*pi,angles(:,2)/180*pi,squeeze(pc_weights(u,:,pc))');
            [cr(sho,u,pc,:,1),cr(sho,u,pc,:,2),cr(sho,u,pc,:,3)] = sph2cart(angles(:,1)/180*pi,angles(:,2)/180*pi,squeeze(pc_weights_rc(sho,u,:,pc)));
            sh_e(sho,u,pc,:) = sqrt(sum((squeeze(co(u,pc,:,:)) - squeeze(cr(sho,u,pc,:,:))).^2,2));
        end
        % Weight Error -- This may need to be replaced by the RMS
        % Shape reconstruction error 
        e_pcw(sho,u,:,:) = abs(abs(squeeze(pc_weights(u,:,:))) - abs(squeeze(pc_weights_rc(sho,u,:,:))));%./abs(squeeze(pc_weights(u,:,:)));
        % Reconstruct HRTF
        t = squeeze(pc_weights_rc(sho,u,:,:)) * pcs(:,:)';
        rec_t(sho,u,1:size(hrirs,2),1,1:(size(hrirs,4)/2)) = t(:,1:size(hrirs,4)/2);
        rec_t(sho,u,1:size(hrirs,2),2,1:(size(hrirs,4)/2)) = t(:,(size(hrirs,4)/2+1):size(hrirs,4));
        hrtf_rec(sho,u,:,:,:) = squeeze(rec_t(sho,u,:,:,:))+ squeeze(pca_mean(u,:,:,:)); % + squeeze(mean_pca(u,:,:,:));
        % Reconstruct Min-Phase HRIR
        for a = 1:size(hrirs,2)
            [hrir_rec(sho,u,a,1,:), hrir_rec(sho,u,a,2,:)] = ifft_minph(squeeze(hrtf_rec(sho,u,a,1,:)),squeeze(hrtf_rec(sho,u,a,2,:)),itd_samples(u,a),size(hrirs,4),2);
        end
    end
            
    e_dtf(sho,:,:,:) = sqrt(mean((squeeze(hrtf_rec(sho,:,:,:,:)) - org_spc).^2,4));
end

% for pc = 1:max_pc
%     for u = 1:size(hrirs,1)    
%         [co(u,pc,:,1),co(u,pc,:,2),co(u,pc,:,3)] = sph2cart(angles(:,1)/180*pi,angles(:,2)/180*pi,squeeze(pc_weights(u,:,pc))');
%         for sho = 1:(max_sh_order+1)            
%             [cr(sho,u,pc,:,1),cr(sho,u,pc,:,2),cr(sho,u,pc,:,3)] = sph2cart(angles(:,1)/180*pi,angles(:,2)/180*pi,squeeze(pc_weights_rc(sho,u,:,pc)));
%             sh_e(sho,u,pc) = sqrt(mean(sum((squeeze(co(u,pc,:,:)) - squeeze(cr(sho,u,pc,:,:))).^2,2)));
%             % sh_e = x - xr etc ... 
%                 % In order to Plot you need to remap the positions to
%                 % create the matrix
%         end
%     end
% end


if freq_mode == 2
    hrtf_mag = 10.^(hrtf_rec/20);
    org_spc = 10.^(org_spc/20);
end

% Plot RMS PCW Shape Reconstruction Error per PC as a function of SH Order
figure(1);
errorbar(repmat((0:(max_sh_order))',[1 max_pc]),squeeze(mean(mean(sh_e,2),4)),squeeze(std(mean(sh_e,4),0,2))/sqrt(size(hrirs,1)));
legend(cellstr(num2str((1:max_pc)', 'PC=%-d')))

% Plot HRTf Reconstruction Error All PCs taken into account
figure(2);
md = squeeze(mean(mean(mean(e_dtf,3),2),4));
sd = squeeze(std(std(std(e_dtf,0,3),0,2),0,4));
figure(2),errorbar(1:size(md,1),md,sd);

% Plot HRIR RMS Reconstruction Error - Need to consider doing the pca with
% the minimum phase and eveloped hrirs to allow for a nice comparison

% Detailed Plots

% Mean Across Subjects for Weight Reconstruction Error
mw = squeeze(mean(sh_e(:,:,1:max_pc,:),2));

for pc = 1:max_pc
    up_lw = ceil(max(max(mw)));
    lo_lw = floor(min(min(mw)));
    figure(pc+3);
    for sh = 1:size(mw,1)    
        subplot(size(mw,1)/2,2,sh);
        spherical_plot(angles,squeeze(mw(:,pc,:)));
%         caxis([lo_lw up_lw]);
    end            
end


me = squeeze(mean(e_dtf,2));
up_le = ceil(max(max(me)));
lo_le = floor(min(min(me)));
for sho = 1:(max_sh_order+1)
    figure(1); % Left Ear
    subplot(ceil((max_sh_order+1)/2),3,sho);
    spherical_plot(angles,squeeze(me(:,:,1)));
%     caxis([lo_le up_le]);    
    
    figure(2); % Right Ear
    subplot(ceil((max_sh_order+1)/2),3,sho);
    spherical_plot(angles,squeeze(me(:,:,1)));
%     caxis([lo_le up_le]);    
end




% Save for Documentation
% Save as EPS
% set(1,'paperunits','centimeters','paperposition',[1 1 12 7])
% saveas(1,sprintf('../thesis/images/error/%s_hrtf_freqmode%i_recon_sh_order_pcs',db,freq_mode),'epsc');




% Save for Documentation
% Save as EPS
% set(1,'paperunits','centimeters','paperposition',[1 1 12 7])
% saveas(2,sprintf('../thesis/images/error/%s_hrtf_freqmode%i_recon_sh_order',db,freq_mode),'epsc');


% Plot Weight Values
pyramid_plot(cell2mat(sh_weights(max_sh_order,:)),max_sh_order);
% Statistical Shape Analysis

% rmpath ./sh/shtools/

% Comparisons

% Get Min Phase HRIRS and ITDs, it might be a good idea after min phase
% calculation to envelope the Hrirs to avoid early reflections from the
% floor etc, what would be the time after which Hrir is zero? 
% hrirs = hrirs([1:27 29:50],:,:,:);
for u = 1:size(hrirs,1)
    for a = 1:size(hrirs,2)
        [k,mphrirs(u,a,1,:)] = rceps(squeeze(hrirs(u,a,1,:)));
        [k,mphrirs(u,a,2,:)] = rceps(squeeze(hrirs(u,a,2,:)));
        [xx,xx,xx,itd_samples(u,a)] = calculate_itd(squeeze(hrirs(u,a,1,:)),squeeze(hrirs(u,a,2,:)),fs);
    end
end


dc_weights = zeros(1,size(sha,1)); dc_weights(1) = 1;
beam_weights = 0.5*SHCreateYVec(sh_order,0,90,'deg') + 0.5*dc_weights';
beam_inv = sha'*beam_weights;
filt = beam_inv.*squeeze(pc_weights_rc(1,:,1))';
filt_ssh = (sha*sha')\sha*squeeze(filt);

th = angles(:,1);
ph = (90-angles(:,2));
[TH,PH] = meshgrid(th/180*pi,ph/180*pi);
for l = 1:size(TH,1)
    for m = 1:size(PH,2)
        a(l,m,:) = SHCreateYVec(sh_order,TH(l,m),PH(l,m),'rad');
    end
end

plot_wsh(TH,PH,a,beam_weights);
plot_wsh(TH,PH,a,sh_weights(u,:,1));
plot_wsh(TH,PH,a,filt_ssh);

play_sh(sh_order,sh_weights(u,:,1),angles);

hrtf_mag = rec_t + repmat(pca_mean,[1 size(rec_t,2) 1 1]);

% Check Spectrum Reconstruction
figure(1);clf;hold on; 
plot(abs(fft(squeeze(hrirs(u,1,1,:)))),'k');
plot(hrtf_mag(u,1,1,:),'r');

phase_l = angle(fft(squeeze(hrirs(u,1,1,:))));
mag_l = abs(fft(squeeze(hrirs(u,1,1,:))));
x = real(ifft(mirror(hrtf_mag(u,1,1,:)').*exp(1i*phase_l),size(hrirs,4)));

% Check HRIR mit Original PHase
figure(2);clf;hold on;
plot(squeeze(hrirs(u,1,1,:)),'k');
plot(x,'r');

% Check Minimum Phase Reconstruction
[xx,xx,xx,itd_samples] = calculate_itd(squeeze(hrirs(1,1,1,:)),squeeze(hrirs(1,1,2,:)),fs);
[hrir_reconstr_left, hrir_reconstr_right] = ifft_minph(hrtf_mag(u,1,1,:),hrtf_mag(u,1,2,:),itd_samples,size(hrirs,4));
figure(3)
[z,y] = rceps(squeeze(hrirs(u,1,1,:)));
plot(y,'m');
plot(hrir_reconstr_left,'b');

end

