classdef DataVisualize
    properties
        ImageFolder % Folder containing images
        ResultsPath % Path for results
    end
    
    methods
        function obj = DataVisualize(imageFolder, resultsPath)
            % Constructor to initialize properties
            obj.ImageFolder = imageFolder;
            obj.ResultsPath = resultsPath;
        end
        
        function makePlot(obj)
            % Define arrays for line widths, colors, and styles
            lineWidths     = [1, 1.5, 2, 2.5];
            lineColors     = {'blue', 'red', 'blue', 'red'};
            lineStyles     = {'-', '--', ':', '-.'};
            wavelengths    = [735, 800, 865, 930]; 
            names          = {'Ester', 'Siem'};

            % Initialize a figure 
            figure;
            prefixes       = {'Avg reflection', 'Avg si'};

            for k = 1:length(prefixes)
                % Create subplots
                subplot(2, 2, k);
                for j = 1:2
                    data = load(sprintf('%s %d.mat', prefixes{k}, j));
                    if k == 1
                        errorbar(wavelengths, data.avg_refl, data.rf_std_error, ...
                            'LineWidth', lineWidths(3), ...
                            'Color', lineColors{j}, ...
                            'LineStyle', lineStyles{1}, ...
                            'CapSize', 10);
                    else
                        errorbar(wavelengths, data.avg_si_refl, data.si_std_error, ...
                            'LineWidth', lineWidths(3), ...
                            'Color', lineColors{j}, ...
                            'LineStyle', lineStyles{1}, ...
                            'CapSize', 10);
                    end
                    hold on;
                end
                
                % Set labels and title
                xlabel('Wavelength (nm)');
                ylabel(prefixes{k});
                set(gca, 'XTick', wavelengths, 'XTickLabel', string(wavelengths));
                grid on;
                title(sprintf('Wavelength vs. %s of %s', prefixes{k}, names{1}));
                legend('Before', 'After');

                % Second subplot
                subplot(2, 2, k + 2);
                for j = 3:4
                    data_siem = load(sprintf('%s %d.mat', prefixes{k}, j));
                    if k == 1
                        errorbar(wavelengths, data_siem.avg_refl, data_siem.rf_std_error, ...
                            'LineWidth', lineWidths(3), ...
                            'Color', lineColors{j}, ...
                            'LineStyle', lineStyles{1}, ...
                            'CapSize', 10);
                    else
                        errorbar(wavelengths, data_siem.avg_si_refl, data_siem.si_std_error, ...
                            'LineWidth', lineWidths(3), ...
                            'Color', lineColors{j}, ...
                            'LineStyle', lineStyles{1}, ...
                            'CapSize', 10);
                    end
                    hold on;
                end
                
                % Set labels and title
                xlabel('Wavelength (nm)');
                ylabel(prefixes{k});
                set(gca, 'XTick', wavelengths, 'XTickLabel', string(wavelengths));
                grid on;
                title(sprintf('Wavelength vs. %s of %s', prefixes{k}, names{2}));
                legend('Before', 'After');
            end
            
            % Save the figure
            saveas(gcf, fullfile(obj.ResultsPath, 'average_and_si.png'));
            hold off; % Release the plot
        end
        
        function changeOfY(obj, roi)
            % This function calculates the percentage decrease of avg si before relative to after
            results = {}; % Initialize a cell array to store results
            for i = 1:2:4 
                name     = 'Ester';
                if i > 2
                    name = 'Siem';
                end
                
                % Load the result of before pressure       
                before              = load(sprintf('Avg si %d.mat', i));
                % Load the result of after pressure
                after               = load(sprintf('Avg si %d.mat', i + 1));
                % Store results in a cell array
                results{end + 1, 1} = name; % Store the name
                results{end, 2}     = string(roi); % Store the roi
                for j = 1:length(after.avg_si_refl)
                    % Calculate the difference and store it at index j
                    results{end, j + 2} = abs(after.avg_si_refl(j) - before.avg_si_refl(j)) / after.avg_si_refl(j) * 100;
                end 
            end 
            
            % Convert results to a table
            resultsTable   = cell2table(results, 'VariableNames', {'Name', 'ROI', 'Band1', 'Band2', 'Band3', 'Band4'});
            
            % Define the output file path
            outputFilePath = fullfile(obj.ResultsPath, 'percentage_decrease_results.csv');
            
            % Check if the file exists
            if isfile(outputFilePath)
                % Append to the existing file
                writetable(resultsTable, outputFilePath, 'WriteMode', 'append', 'WriteVariableNames', false);
            else
                % Write the table to a new CSV file
                writetable(resultsTable, outputFilePath);
            end
        end
        
        function [position, x, y] = regionOfInterest(obj, roi)
            % Get all image files from the specified folder
            imageFiles = dir(fullfile(obj.ImageFolder, '*.png')); % Adjust file extension as needed

            if isempty(imageFiles)
                disp('No images found in the specified folder.');
                return; % Exit if no images are found
            end

            % Select an image from the folder
            selectedImageFile = imageFiles(1).name;
            firstImagePath    = fullfile(obj.ImageFolder, selectedImageFile); % Full path to the selected image
            
            % Load the selected image
            img               = imread(firstImagePath);
            % Convert the image to grayscale
            gray_image        = im2gray(img);

            % Get the size of the grayscale image
            [x, y]            = size(gray_image);
            if ~roi
                position      = [];
            else
                % Extract the top-left quarter of the image
                img_quarter   = gray_image(floor(x/2):x, floor(y/2):y);
                imshow(img_quarter); % Display the original image
                title('Draw the ROIs '); % Title for clarity
                hold on; % Hold on to overlay the ROIs
                
                % Create a freehand ROI
                h            = imfreehand(gca); % Draw freehand ROI
                
                % Wait for the user to finalize the ROI
                position     = getPosition(h); % Get the coordinates of the ROI

                % Highlight points on the image using red circles
                if ~isempty(position)  % Ensure there are positions to plot
                    xCoords  = position(:, 1); % Extract X coordinates
                    yCoords  = position(:, 2); % Extract Y coordinates

                    % Highlight points on the image
                    plot(xCoords, yCoords, 'r*', 'MarkerSize', 2, 'LineWidth', 0.5); % Red circles
                    % Optionally, connect the points with lines
                    plot(xCoords, yCoords, 'b-', 'LineWidth', 0.5); % Red lines connecting points
                    title('Specific ROIs'); % Title for clarity
                    saveas(gcf, fullfile(obj.ResultsPath, 'Specific_roi.png'));
                end
                hold off; % Release the hold on the current figure
            end  
        end
    end
end
