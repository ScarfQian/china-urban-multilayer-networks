function Tfull = m11_load_city_codebook_full_313(codebookPath, templatePath, varargin)
% M11_LOAD_CITY_CODEBOOK_FULL_313
% Expand the current partial city2pro codebook into a full 313-city codebook.

p = inputParser;
p.addRequired('codebookPath', @(x) ischar(x) || isstring(x));
p.addRequired('templatePath', @(x) ischar(x) || isstring(x));
p.addParameter('OutputCsv', "", @(x) ischar(x) || isstring(x));
p.parse(codebookPath, templatePath, varargin{:});
opt = p.Results;

Tcode = readtable(codebookPath, 'TextType', 'string');
Tcode.province_code = double(Tcode.province_code);
Tcode.city_code = double(Tcode.city_code);
Tcode.city_name_std = string(Tcode.city_name_std);
Tcode.province_name_std = string(Tcode.province_name_std);
Tcode.city_name_norm = normalize_city_name_cn_codebook(Tcode.city_name_std);

Ttemplate = readtable(templatePath, 'TextType', 'string');
Ttemplate.city_id = double(Ttemplate.city_id);
Ttemplate.city_en = string(Ttemplate.city_en);
Ttemplate.city_cn = string(Ttemplate.city_cn);
Ttemplate.city_name_norm = normalize_city_name_cn_codebook(Ttemplate.city_cn);

Tsupp = manual_city_code_supplement_40();
Tsupp.city_name_norm = normalize_city_name_cn_codebook(Tsupp.city_cn);

provinceNameEn = province_name_en_map();
provinceCodeByName = province_code_by_name();

cityCode = zeros(height(Ttemplate), 1);
provinceCode = zeros(height(Ttemplate), 1);
provinceNameStd = strings(height(Ttemplate), 1);
provinceNameEnCol = strings(height(Ttemplate), 1);
sourceTag = strings(height(Ttemplate), 1);

for i = 1:height(Ttemplate)
    hit = find(Tcode.city_name_std == Ttemplate.city_cn(i), 1, 'first');
    if isempty(hit)
        hit = find(Tcode.city_name_norm == Ttemplate.city_name_norm(i), 1, 'first');
    end
    if ~isempty(hit)
        cityCode(i) = Tcode.city_code(hit);
        provinceCode(i) = Tcode.province_code(hit);
        provinceNameStd(i) = Tcode.province_name_std(hit);
        if isKey(provinceNameEn, char(provinceNameStd(i)))
            provinceNameEnCol(i) = provinceNameEn(char(provinceNameStd(i)));
        end
        sourceTag(i) = "existing_codebook";
        continue;
    end

    hit2 = find(Tsupp.city_cn == Ttemplate.city_cn(i), 1, 'first');
    if isempty(hit2)
        hit2 = find(Tsupp.city_name_norm == Ttemplate.city_name_norm(i), 1, 'first');
    end
    if isempty(hit2)
        error('m11_load_city_codebook_full_313:MissingManualSupplement', ...
            'City %s is not covered by the existing codebook or the manual supplement.', ...
            Ttemplate.city_cn(i));
    end
    cityCode(i) = Tsupp.city_code(hit2);
    provinceCode(i) = Tsupp.province_code(hit2);
    provinceNameStd(i) = Tsupp.province_name_std(hit2);
    if isKey(provinceNameEn, char(provinceNameStd(i)))
        provinceNameEnCol(i) = provinceNameEn(char(provinceNameStd(i)));
    end
    sourceTag(i) = "manual_supplement";
end

provinceId = zeros(height(Ttemplate), 1);
for i = 1:height(Ttemplate)
    provinceId(i) = provinceCodeByName(char(provinceNameStd(i)));
end

Tfull = table( ...
    Ttemplate.city_id, ...
    Ttemplate.city_en, ...
    Ttemplate.city_cn, ...
    provinceId, ...
    provinceNameEnCol, ...
    provinceNameStd, ...
    provinceCode, ...
    cityCode, ...
    sourceTag, ...
    'VariableNames', {'city_id','city_en','city_cn','province_id','province_en','province_name_std','province_code','city_code','code_source'});

if strlength(string(opt.OutputCsv)) > 0
    writetable(Tfull, string(opt.OutputCsv));
end
end

function out = normalize_city_name_cn_codebook(in)
out = string(in);
out = strtrim(out);
suffixes = ["市","地区","盟","自治州","特别行政区","省直辖县级行政区划","自治区直辖县级行政区划"];
for i = 1:numel(suffixes)
    out = erase(out, suffixes(i));
end
end

function M = province_name_en_map()
keys = {'北京市','天津市','河北省','山西省','内蒙古自治区','辽宁省','吉林省','黑龙江省', ...
    '上海市','江苏省','浙江省','安徽省','福建省','江西省','山东省','河南省','湖北省','湖南省', ...
    '广东省','广西壮族自治区','海南省','重庆市','四川省','贵州省','云南省','西藏自治区', ...
    '陕西省','甘肃省','青海省','宁夏回族自治区','新疆维吾尔自治区'};
vals = {'Beijing','Tianjin','Hebei','Shanxi','Inner Mongolia','Liaoning','Jilin','Heilongjiang', ...
    'Shanghai','Jiangsu','Zhejiang','Anhui','Fujian','Jiangxi','Shandong','Henan','Hubei','Hunan', ...
    'Guangdong','Guangxi','Hainan','Chongqing','Sichuan','Guizhou','Yunnan','Xizang', ...
    'Shaanxi','Gansu','Qinghai','Ningxia','Xinjiang'};
M = containers.Map(keys, vals);
end

function M = province_code_by_name()
keys = {'北京市','天津市','河北省','山西省','内蒙古自治区','辽宁省','吉林省','黑龙江省', ...
    '上海市','江苏省','浙江省','安徽省','福建省','江西省','山东省','河南省','湖北省','湖南省', ...
    '广东省','广西壮族自治区','海南省','重庆市','四川省','贵州省','云南省','西藏自治区', ...
    '陕西省','甘肃省','青海省','宁夏回族自治区','新疆维吾尔自治区'};
vals = num2cell((1:31)');
M = containers.Map(keys, vals);
end

function T = manual_city_code_supplement_40()
city_cn = [ ...
    "兴安盟";"锡林郭勒";"阿拉善盟";"延边";"大兴安岭";"莱芜";"济源";"恩施州"; ...
    "仙桃";"神农架地区";"天门";"潜江";"湘西";"海南";"甘孜";"阿坝";"凉山"; ...
    "毕节";"铜仁";"黔东南";"黔南";"黔西南";"云南";"西藏";"临夏";"甘南"; ...
    "青海";"吐鲁番";"哈密";"昌吉";"伊犁";"阿勒泰";"博尔塔拉";"巴音郭楞"; ...
    "阿克苏";"喀什";"和田";"石河子";"克孜";"塔城"];

province_name_std = [ ...
    "内蒙古自治区";"内蒙古自治区";"内蒙古自治区";"吉林省";"黑龙江省";"山东省";"河南省";"湖北省"; ...
    "湖北省";"湖北省";"湖北省";"湖北省";"湖南省";"海南省";"四川省";"四川省";"四川省"; ...
    "贵州省";"贵州省";"贵州省";"贵州省";"贵州省";"云南省";"西藏自治区";"甘肃省";"甘肃省"; ...
    "青海省";"新疆维吾尔自治区";"新疆维吾尔自治区";"新疆维吾尔自治区";"新疆维吾尔自治区";"新疆维吾尔自治区";"新疆维吾尔自治区";"新疆维吾尔自治区"; ...
    "新疆维吾尔自治区";"新疆维吾尔自治区";"新疆维吾尔自治区";"新疆维吾尔自治区";"新疆维吾尔自治区";"新疆维吾尔自治区"];

province_code = [ ...
    150000;150000;150000;220000;230000;370000;410000;420000; ...
    420000;420000;420000;420000;430000;460000;510000;510000;510000; ...
    520000;520000;520000;520000;520000;530000;540000;620000;620000; ...
    630000;650000;650000;650000;654000;654300;652700;652800; ...
    652900;653100;653200;659001;653000;654200];

city_code = [ ...
    152200;152500;152900;222400;232700;371200;419001;422800; ...
    429004;429021;429006;429005;433100;460000;513300;513200;513400; ...
    520500;520600;522600;522700;522300;530000;540000;622900;623000; ...
    630000;650400;650500;652300;654000;654300;652700;652800; ...
    652900;653100;653200;659001;653000;654200];

T = table(city_cn, province_name_std, province_code, city_code);
end
