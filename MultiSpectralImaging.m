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
        
        function obj  = runMultiSpectral(obj, imageDir, numImages, dir_ind, position, isNormalized)
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
            fields   = {'avg_refl', 'rf_std_error', 'avg_si_refl', 'si_std_error'};
            for i = 1:length(fields)
               data.(fields{i}) = zeros(1, obj.total_bands);
            end
            % Process images in groups of numImages
            for i = 1:numImages
                % Construct the full file name
                filename       = fullfile(imageDir, imageFiles(i).name);
                
                % Check if the file exists
                if isfile(filename)
                    % Read the image and Smooth it using imbilatfilt
                    img        =imread(filename);
                    % Convert to grayscale if the image is RGB
                    if size(img, 3) == 3
                        img     = rgb2gray(img);
                    end
                    % Convert to double
                    img=double(img);
                    % Update img_bands using one line
                    for channel = 1:obj.total_bands
                        new_img =obj.crop_image(img, channel, position);
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
                    avg_img            =(img_bands{j}./ numImages);
                    % Increment num_images for each succesi  ppsfully processed image
                    obj.num_images      = obj.num_images + 1; 
                    % Convert to uint8
                    avg_uint8           =uint8(avg_img);
                    % Calculate K/S or average si
                    si                  =obj.cal_absop_to_scatt_ratio(avg_img);
                    %Convert to uint8
                    si_uint8            =uint8(si);
                    % Normalize the image
                    if isNormalized==true
                       si                  =obj.normalize_image(si,j, position);
                       si_uint8            =uint8(si*255);
                       avg_img             =obj.normalize_image(avg_img, j, position);
                       avg_uint8           =uint8(avg_img*255);
                    end
                    %Calculate Avg reflection ans Si
                    data.rf_std_error(j)   = std2(avg_uint8) / sqrt(numel(avg_uint8)); % Standard error calculation
                    data.avg_refl(j)       = mean2(avg_uint8);  
                    data.avg_si_refl(j)    = mean2(si_uint8);
                    data.si_std_error(j)   = std2(si_uint8)/ sqrt(numel(si_uint8));
                    % Store the processed image
                    obj.si_images{obj.num_images} = si_uint8;
                    % Display the fourth band images before and after
                    % pressure
                    if dir_ind==1 || dir_ind==2 && j==4 
                        pos=@(d) (d == 1) * 1 + (d ~= 1) * 3;% is used to for position separation
                        subplot(2,2,pos(dir_ind));
                        imshow(avg_uint8);
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
             rows      =[1 obj.width/2;obj.width/2+1 obj.width];
             cols      =[1 obj.height/2;obj.height/2+1 obj.height];
            
            % Check if the dimensions are even
            if mod(obj.width, 2) ~= 0 || mod(obj.height, 2) ~= 0
                error('Image dimensions must be even.');
            end
            % Define the row and column indices for each band
           row_indices = [rows(1,1), rows(1,2); rows(1,1), rows(1,2); rows(2,1), rows(2,2); rows(2,1), rows(2,2)];
           col_indices = [cols(1,1), cols(1,2); cols(2,1), cols(2,2); cols(1,1), cols(1,2); cols(2,1), cols(2,2)];
           new_img     =img(row_indices(j, 1):row_indices(j, 2), col_indices(j, 1):col_indices(j, 2));
           if obj.roi==true
               % Extract the First ROI Positions
                  x        = position(:, 1);
                  y        = position(:, 2);

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
        
        function normalize_img=normalize_image(obj, img,j, position)
                 % Normalize an image using specified white and dark reference images.  
                 % Check for the existence of the white reference image
                if exist('C:\\Users\\DELL\\Documents\\MATLAB\\res\\images\\w.png', 'file') ~= 2
                     error('White reference image (w.png) not found.');
                end

                 %Check for the existence of the dark reference image
                if exist('C:\\Users\\DELL\\Documents\\MATLAB\\res\\images\\b.png', 'file') ~= 2
                     error('Dark reference image (b.png) not found.');
                end

                % Read and convert the images to grayscale
                white = imread('C:\\Users\\DELL\\Documents\\MATLAB\\res\\images\\w.png');
                dark  = imread('C:\\Users\\DELL\\Documents\\MATLAB\\res\\images\\b.png');
                if size(white,3)==3
                    white=rgb2gray(white);
                end
                if size(dark,3)==3
                    dark=rgb2gray(dark);
                end
                white = double(white);
                dark  = double(dark);

                % Check if the sizes of white and dark images are the same
                if ~isequal(size(white), size(dark))
                    error('White and dark reference images must be of the same size.');
                end

                 % Check for division by zero
                 if all(white(:) == dark(:))
                  error('White and dark reference images are identical. Normalization cannot be performed.');
                end
                cropped_dark  = obj.crop_image(dark, j, position);
                cropped_white = obj.crop_image(white, j, position);
                % Normalize the image
                normalize_img = (img - cropped_dark) ./(cropped_white - cropped_dark);
                % Optional: Handle potential NaN values in the normalized image
                normalize_img(isnan(normalize_img)) = 0; % Replace NaNs with 0 (or another value if needed)
                
        end

        function si = cal_absop_to_scatt_ratio(~, img)
            % Check if the input image is valid
            if isempty(img) || ~isnumeric(img)
                error('Input image must be a non-empty numeric array.');
            end
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
        function output = status(~, d)
                if d == 1 || d==3
                   output = "Before";
                else
                  output = "After";
               end
       end
    end
end
