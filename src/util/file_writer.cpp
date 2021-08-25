#ifndef __FILEWRITER__
#define __FILEWRITER__
#include"../head.hpp"

using namespace std;

FileWriter::FileWriter(std::string filename,std::string seperator, bool overwrite) //构造函数
{
    _filename = filename;
    if (_filename.empty()) {
        LOG << ERROR << "No output file is specified." << std::endl;
        return;
    }
    string splitePattern;
    if (seperator.empty() || trim(seperator).empty()) {
        LOG << DEBUG << "Using default write seperator [" + DEFAULT_SPLIT_PATTERN + "]." << std::endl;
        splitePattern = DEFAULT_SPLIT_PATTERN;
    }
    else {
        splitePattern = trim(seperator);
        LOG << INFO << "Write seperator set as [" + splitePattern + "]."<< std::endl;
    }
    _seperator = splitePattern;
    if(overwrite){
        //创建文件或删除原有内容
        LOG << INFO << "The original contents of the file will be deleted:" + _filename<< std::endl;
        _outfile = std::ofstream(_filename.c_str(), std::ios::trunc);
    }
    else{
        //创建文件或文件存在时追加
        LOG << INFO << "Writer will append to:" + _filename<< std::endl;
        _outfile = std::ofstream(_filename.c_str(), std::ios::app);
    }
    if(_outfile.is_open()){
       LOG << DEBUG << (_filename + " is open") << std::endl;
    }
    else{
        LOG << ERROR << ("File open error: " + _filename) << std::endl;
    }
    
}

bool FileWriter::good()
{
    return _outfile.good();
}

bool FileWriter::writeLine(std::string& line) 
{
    if (_outfile.good()) {
        _outfile << line <<endl;
        return true;
    }
    else {
        LOG << DEBUG << "FileWriter::writeLine(string&) _outfile.good() == false" << std::endl;
        return false;
    }
    return false;
}

bool  FileWriter::constructLineAndWrite(std::vector<std::string> strings) 
{
    if (_outfile.good()) {
        size_t length = strings.size();
        if(0 == length){
            LOG << DEBUG << "FileWriter::constructLineAndWrite(vector<string>) skip an empty line." << std::endl;
            return true;
        }
        for (size_t i=0;i<length;i++)
        {
            _outfile << strings[i];
            if(i==length-1){
                _outfile << endl;
            }
            else{
                _outfile << _seperator;
            }
        }
        return true;
    }
    else {
        LOG << DEBUG << "FileWriter::constructLineAndWrite(vector<string>) _outfile.good() == false" << std::endl;
        return false;
    }
    return false;
}

string FileWriter::getFilename() {
    return _filename;
}

string FileWriter::trim(const std::string& s) 
{
    string temp = s;
    if (temp.empty()){
        return "";
    }
    else{
        temp.erase(0,temp.find_first_not_of(" "));
        temp.erase(temp.find_last_not_of(" ") + 1);
    }
    return temp;
}

#endif
