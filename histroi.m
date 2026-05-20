function [mean_depth,std_depth,min_depth,max_depth, mean_intensity] = histroi(depth_double, intensity_double, Xreg, Yreg, zeroed)

ROI_depth = depth_double(Xreg(2):Yreg(2), Xreg(1):Yreg(1));
ROI_unroll_depth = ROI_depth(:);
ROI_nozero_depth = ROI_unroll_depth(ROI_unroll_depth>0);

if zeroed==0
    std_depth = std(ROI_nozero_depth);
    mean_depth = mean(ROI_nozero_depth);
    min_depth = min(ROI_nozero_depth);
    max_depth = max(ROI_nozero_depth);
else
    std_depth = std(ROI_unroll_depth);
    mean_depth = mean(ROI_unroll_depth);
    min_depth = min(ROI_unroll_depth);
    max_depth = max(ROI_unroll_depth);
end

ROI_intensity = intensity_double(Xreg(2):Yreg(2), Xreg(1):Yreg(1));
ROI_unroll_intensity = ROI_intensity(:);
ROI_nozero_intensity = ROI_unroll_intensity(ROI_unroll_intensity>0);
if zeroed==0
    mean_intensity = mean(ROI_nozero_intensity);
else
    mean_intensity = mean(ROI_unroll_intensity);
end


figure;
subplot(3,1,3)
histogram(ROI_nozero_depth);
title("RoI Histogram")
xlabel('Depth (cm)');
subplot(3,1,1)
imagesc(ROI_depth);
title("Region of Interest - Depth")
axis image;
subplot(3,1,2)
imagesc(ROI_intensity);
title("Region of Interest - Intensity")
axis image;

end