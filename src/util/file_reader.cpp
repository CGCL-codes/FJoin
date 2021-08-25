#ifndef __FILEREADER__
#define __FILEREADER__

#include"../head.hpp"

using namespace std;
FileReader::FileReader(string filename, string splitPunc) //构造函数
{
    _filename = filename;
    getIfstream();
    string splitePattern;
    if (splitPunc.empty() || trim(splitPunc).empty()) {
        LOG << DEBUG << "Using default read seperator [" + DEFAULT_SPLIT_PATTERN + "]." << std::endl;
        splitePattern = DEFAULT_SPLIT_PATTERN;
    }
    else {
        splitePattern = trim(splitPunc);        
        LOG << INFO << "Read seperator set as [" + splitePattern + "]."<< std::endl;
    }
    _seperator = splitePattern;
}

void FileReader::getIfstream() 
{
    if (_filename.empty()) {
        LOG << DEBUG << "No input file is specified." << std::endl;
        return;
    }
    _infile = std::ifstream(_filename.c_str(), std::ifstream::in);

    if(_infile.is_open()){
       LOG << DEBUG << (_filename + " is open") << std::endl;
    }
    else{
        LOG << ERROR << ("File not exists: " + _filename) << std::endl;
    }
}

bool FileReader::good()
{
    return _infile.good();
}

std::vector<std::string> FileReader::SplitString(const std::string& s, const std::string& seperator)
{
    vector<string> result;
    std::string::size_type pos1, pos2;
    pos2 = s.find(seperator);
    pos1 = 0;
    while(std::string::npos != pos2)
    {
        result.push_back(s.substr(pos1, pos2-pos1));

        pos1 = pos2 + seperator.size();
        pos2 = s.find(seperator, pos1);
    }
    if(pos1 != s.length())  result.push_back(s.substr(pos1));
    return result;
}
    
string FileReader::readLine() 
{
    string temp;
    if (getline(_infile,temp)) {
        return temp;
    }
    else {
        LOG << DEBUG << "FileReader::readLine() getline(_infile,temp) == false" << std::endl;
        return "";
    }
}

std::vector<std::string> FileReader::readLineAndSplit() 
{
    string line = readLine();
    vector<string> result;
    std::string::size_type pos1, pos2;
    pos2 = line.find(_seperator);
    pos1 = 0;
    while(std::string::npos != pos2)
    {
        result.push_back(line.substr(pos1, pos2-pos1));
        pos1 = pos2 + _seperator.size();
        pos2 = line.find(_seperator, pos1);
    }
    if(pos1 != line.length())  result.push_back(line.substr(pos1));
    return result;

}

string FileReader::getFilename() {
    return _filename;
}

string FileReader::trim(string &s) 
{
    string temp;
    if (s.empty()){
        ;
    }
    else{
        s.erase(0,s.find_first_not_of(" "));
        s.erase(s.find_last_not_of(" ") + 1);
    }
    return temp = s;
}

#endif