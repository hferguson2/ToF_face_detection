function modify_config(lens_mode)

jsonText = fileread('C:\Program Files\LIPSToF\ModuleConfig.json');

% Convert JSON formatted text to MATLAB data types (3x1 cell array in this example)
jsonData = jsondecode(jsonText); 

% Change lens_mode value in config (Row 5), 1 for normal, 0 for short range
jsonData.config.lens_mode = lens_mode;

% Convert to JSON text_
jsonText2 =  jsonencode(jsonData,'PrettyPrint',true);

% Write to a json file, make sure you have owner access
fid = fopen('C:\Program Files\LIPSToF\ModuleConfig.json', 'w');
fprintf(fid, '%s', jsonText2);
fclose(fid);

%copyfile('.\ModuleConfig.json', 'C:\Program Files\LIPSToF\', 'f');