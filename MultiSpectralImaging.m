classdef MultiSpectralImaging
    properties
        wavelengths; % Should be a vector of wavelengths
        total_bands; % Number of bands
        roi; 
        si_images; % Cell array to hold processed images
        height;
        width;
    end
    properties (Access = private)
        num_images % Property to store the cumulative count of processed images
    end

    methods
        function obj = MultiSpectralImaging(wavelengths, total_bands, roi, x, y) 
            obj.wavelengths = wavelengths;
            obj.total_bands = total_bands;
            obj.roi         = roi;
            obj.si_images   = {};
            obj.num_images  = 0; % Initialize count to zero
            obj.width       =x;
            obj.height      =y;
        end
        
        function obj  = runMultiSpectral(obj, imageDir, numImages, dir_ind, position)
            % Initialize empty image for each band based on the roi value
            img_bands =cell(1, 4);
            for index = 1:4
                img_bands{index}=zeros(obj.width/2, obj.height/2);
            end
            % Create a structure to hold dynamic variable names
            data      = struct();
            % Ensure the directory is formatted correctly
            imageDir  = strrep(imageDir, '\', '\\');
            % Get a list of all PNG files in the directory
            imageFiles= dir(fullfile(imageDir, '*.png'));
            if isempty(imageFiles)
                disp('No images found in the specified directory.');
                return; % Exit the function early
            end
            % Initialize each field of data in a loop
            fields    = {'avg_refl', 'rf_std_error', 'avg_si_refl', 'si_std_error'};
            for i = 1:length(fields)
               data.(fields{i}) = zeros(1, obj.total_bands);
            end
            % Process images in groups of numImages
            for i = 1:numImages
                % Construct the full file name
                filename    = fullfile(imageDir, imageFiles(i).name);
                
                % Check if the file exists
                if isfile(filename)
                    % Read the image and Smooth it using imbilatfilt
                    img     =imbilatfilt(imread(filename));
                    
                    % Convert to grayscale if the image is RGB
                    if size(img, 3) == 3
                        img = rgb2gray(img);
                    end
                    % Update img_bands using one line
                    for channel = 1:obj.total_bands
                        new_img=obj.crop_image(img, channel, position);
                        if size(img_bands{channel}) ~= size(new_img)
                            % Resize img_bands{channel} to the size of croppedROI
                            img_bands{channel}       = imresize(img_bands{channel}, [size(new_img, 1), size(new_img, 2)]);
                        end
                        img_bands{channel}           = img_bands{channel}+new_img;
                    end
                else
                    disp(['Image not found: ', filename]);
                end
            end
            
            for j = 1:obj.total_bands
                if ~isempty(img_bands{j})  
                    [x, y]              = size(img_bands{j});
                    % Increment num_images for each succesi  ppsfully processed image
                    obj.num_images      = obj.num_images + 1; 
                    % Normalize the image
                    img                 = obj.normalize_image(img_bands{j}./ numImages, j, position);
                    %img=im2uint8(img_bands{j}./ numImages);
                    data.rf_std_error(j)= std2(img) / sqrt((x + y)); % Standard error calculation
                    data.avg_refl(j)    = mean2(img);  
                    % Calculate K/S or average si
                    si                  =obj.cal_absop_to_scatt_ratio(img_bands{j});
                    si_uint8            = obj.normalize_image(si./ numImages,j, position);
                    %si_uint8=im2uint8(si./ numImages);
                    data.avg_si_refl(j) = mean2(si_uint8);
                    data.si_std_error(j)= std2(si_uint8) / sqrt((x + y));
                    % Store the processed image
                    obj.si_images{obj.num_images} = si_uint8;
                    % Display the fourth band images before and after
                    % pressure
                    if dir_ind==1 && j==4 ||dir_ind==2 && j==4
                        pos=@(d) (d == 1) * 1 + (d ~= 1) * 3;% is used to for position separation
                        subplot(2,2,pos(dir_ind));
                        imshow(img);
                        title(sprintf("Average image %s Pressure", obj.status(dir_ind)));
                        subplot(2,2,pos(dir_ind)+1);
                        imshow(si_uint8);
                        title(sprintf("Average Si image %s Pressure", obj.status(dir_ind)));
                        hold on;
                    end
                end            
            end
            % Export the result to .mat file
            obj.exportData(data.avg_refl, data.rf_std_error, data.avg_si_refl, data.si_std_error, dir_ind);
        end
        function new_img=crop_image(obj, img, j, position)
            % divide the orginal image into four parts
             rows=[1 obj.width/2;obj.width/2+1 obj.width];
             cols=[1 obj.height/2;obj.height/2+1 obj.height];
            
            % Check if the dimensions are even
            if mod(obj.width, 2) ~= 0 || mod(obj.height, 2) ~= 0
                error('Image dimensions must be even.');
            end
            img_db=im2double(img);
            % Define the row and column indices for each band
           row_indices      = [rows(1,1), rows(1,2); rows(1,1), rows(1,2); rows(2,1), rows(2,2); rows(2,1), rows(2,2)];
           col_indices      = [cols(1,1), cols(1,2); cols(2,1), cols(2,2); cols(1,1), cols(1,2); cols(2,1), cols(2,2)];
           new_img          =img_db(row_indices(j, 1):row_indices(j, 2), col_indices(j, 1):col_indices(j, 2));
           if obj.roi==true
               % Extract the First ROI Positions
                  x         = position(:, 1);
                  y         = position(:, 2);

                  % Create a binary mask using roipoly
                  mask      = roipoly(new_img, x, y);

                 %Find the bounding box of the ROI
                 [row, col] = find(mask); % Get the coordinates of the ROI in the mask
                 % Determine the bounding box
                 xMin       = min(col);
                 xMax       = max(col);
                 yMin       = min(row);
                 yMax       = max(row);
                 %Crop the image using the bounding box
                 new_img    = new_img(yMin:yMax, xMin:xMax, :);
           end
        end
        
        function normalize_img = normalize_image(obj, img,j, position)
                 % Normalize an image using specified white and dark reference images.  
                 % Read the reference images
                % Check for the existence of the white reference image
                if exist('C:\\Users\\DELL\\Documents\\MATLAB\\res\\images\\w.png', 'file') ~= 2
                     error('White reference image (w.png) not found.');
                end

                 %Check for the existence of the dark reference image
                if exist('C:\\Users\\DELL\\Documents\\MATLAB\\res\\images\\b.png', 'file') ~= 2
                     error('Dark reference image (b.png) not found.');
                end

                % Read and convert the images to grayscale
                white = rgb2gray(imread('C:\\Users\\DELL\\Documents\\MATLAB\\res\\images\\w.png'));
                dark  = rgb2gray(imread('C:\\Users\\DELL\\Documents\\MATLAB\\res\\images\\b.png'));

                % Check for division by zero
                if all(white(:) == dark(:))
                     error('White and dark reference images are identical. Normalization cannot be performed.');
                end
                cropped_dark  = obj.crop_image(dark, j, position);
                cropped_white = obj.crop_image(white, j, position);
                % Normalize the image
                normalize_img = (img - cropped_dark) ./(cropped_white - cropped_dark);
                normalize_img = max(0, min(1, normalize_img));  % Clipping to [0, 1]
                normalize_img = uint8(normalize_img * 255);  % Convert back to uint8 for display
        end

        function si = cal_absop_to_scatt_ratio(~, img)
            % Check if the input image is valid
            if isempty(img) || ~isnumeric(img)
                error('Input image must be a non-empty numeric array.');
            end

            %img = im2double(img); % Ensure the image is double
            % Avoid division by zero
            img(img == 0) = 1e-10; % Small value to prevent log(0)

            % Calculate the absorption to scattering ratio for each pixel
            si = ((1 - img).^2) ./ (2 * img);
        end

        function exportData(~, avg_refl, rf_std_error, avg_si_refl, si_std_error, dir_ind)
            % Create dynamic filenames using the provided directory index
            avg_si       = sprintf('Avg si %d', dir_ind);  % Filename for average si data
            avg_Ref      = sprintf('Avg reflection %d', dir_ind); % Filename for average reflection data
            si_filename  = strcat(avg_si, '.mat');      % Complete filename for si data
            avg_filename = strcat(avg_Ref, '.mat');          % Complete filename for reflection data

            % Check if the average reflection file exists and remove it if it does
            if exist(avg_filename, 'file')
                delete(avg_filename);  % Delete the existing file
            end

            % Check if the si file exists and remove it if it does
            if exist(si_filename, 'file')
                delete(si_filename);  % Delete the existing file
            end

            % Save data to the dynamically generated .mat file for average reflection
            save(avg_filename, 'avg_refl', 'rf_std_error');
            % Save data to the dynamically generated .mat file for si values
            save(si_filename, 'avg_si_refl', 'si_std_error');
        end
        function graph_coloring(obj,i)
            % color maping
            name       = "Ester";
            if i>8
                name   = "Siem";
            end
            folder_name="Before";
            image_index=i;
            band_num   = @(i) mod(i, 4) + (mod(i, 4) == 0) * 4; % Define the lambda expression
            figure;
            for j=1:2:4
                % Create a new figure
                if j>1
                    folder_name="After";
                end
                % Calculate mean and standard error
                mean_val = mean2(obj.si_images{image_index}(:));
                std_dev  = std2(obj.si_images{image_index});
                subplot(2,2,j)
                imagesc(obj.si_images{image_index}); % Display the data as an image
                axis square; % Correct the axis orientation
                colorbar; % Add a color bar for reference
                % Step 2: Set color limits for the color map
                clim([40, 90]); % Set color limits between 30 and 100
                % Step 3: Customize the colormap
                colormap(jet); % Change to the 'jet' colormap
                % Add a title using sprintf
                title(sprintf("%s %s Pressure of band %d", name, folder_name, band_num(i))); % Dynamic title   
                xlabel('X'); % Label the X-axis
                ylabel('Y'); % Label the Y-axis
                hold on;
                subplot(2,2,j+1)
                h         = histogram(obj.si_images{image_index}, 30); % Adjust number of bins as needed
                % Find the maximum value of the histogram for positioning text
                max_value = max(h.Values);
                % Add mean and std as text labels
                text('String', sprintf('Mean = %.2f', mean_val), ...
                     'Position', [mean_val+mean_val/10, max_value*0.9], ...
                     'Color', 'r', 'FontSize', 8, 'FontWeight', 'bold');

                 text('String', sprintf('Std = %.2f', std_dev), ...
                      'Position', [mean_val+mean_val/10, max_value*0.8], ...
                      'Color', 'r', 'FontSize', 8, 'FontWeight', 'bold');
                title('Histogram with Mean and Std');
                xlabel('Value');
                ylabel('Count');
                grid on; % Optional: Add grid for better readability 
                image_index=image_index+4;
            end
            saveas(gcf, sprintf('C:\\Users\\DELL\\Documents\\MATLAB\\src\\results\\%s_result_of_band_%d.png', name, band_num(i)));    
            hold off;
            % filename = sprintf('colorImage_of_%s_band_%d.png', name, band_num);
            % % Check if the file exists
            % if isfile(filename)
            %    delete(filename); % Delete the file if it exists
            % end
            % Save the new image
            %saveas(obj.si_images{image_index}, filename); % Save the image using imwrite
        end
        function output = status(~, d)
                if d == 1 || d==3
                   output = "Before";
                else
                  output = "After";
               end
       end
    end
end
