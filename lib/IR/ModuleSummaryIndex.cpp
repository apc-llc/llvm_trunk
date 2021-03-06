//===-- ModuleSummaryIndex.cpp - Module Summary Index ---------------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file implements the module index and summary classes for the
// IR library.
//
//===----------------------------------------------------------------------===//

#include "llvm/IR/ModuleSummaryIndex.h"
#include "llvm/ADT/StringMap.h"
using namespace llvm;

// Create the combined module index/summary from multiple
// per-module instances.
void ModuleSummaryIndex::mergeFrom(std::unique_ptr<ModuleSummaryIndex> Other,
                                   uint64_t NextModuleId) {

  StringRef ModPath;
  for (auto &OtherGlobalValInfoLists : *Other) {
    GlobalValue::GUID ValueGUID = OtherGlobalValInfoLists.first;
    GlobalValueInfoList &List = OtherGlobalValInfoLists.second;

    // Assert that the value info list only has one entry, since we shouldn't
    // have duplicate names within a single per-module index.
    assert(List.size() == 1);
    std::unique_ptr<GlobalValueInfo> Info = std::move(List.front());

    // Skip if there was no summary section.
    if (!Info->summary())
      continue;

    // Add the module path string ref for this module if we haven't already
    // saved a reference to it.
    if (ModPath.empty()) {
      auto Path = Info->summary()->modulePath();
      ModPath = addModulePath(Path, NextModuleId, Other->getModuleHash(Path))
                    ->first();
    } else
      assert(ModPath == Info->summary()->modulePath() &&
             "Each module in the combined map should have a unique ID");

    // Note the module path string ref was copied above and is still owned by
    // the original per-module index. Reset it to the new module path
    // string reference owned by the combined index.
    Info->summary()->setModulePath(ModPath);

    // Add new value info to existing list. There may be duplicates when
    // combining GlobalValueMap entries, due to COMDAT values. Any local
    // values were given unique global IDs.
    addGlobalValueInfo(ValueGUID, std::move(Info));
  }
}

void ModuleSummaryIndex::removeEmptySummaryEntries() {
  for (auto MI = begin(), MIE = end(); MI != MIE;) {
    // Only expect this to be called on a per-module index, which has a single
    // entry per value entry list.
    assert(MI->second.size() == 1);
    if (!MI->second[0]->summary())
      MI = GlobalValueMap.erase(MI);
    else
      ++MI;
  }
}

// Collect for the given module the list of function it defines
// (GUID -> Summary).
void ModuleSummaryIndex::collectDefinedFunctionsForModule(
    StringRef ModulePath,
    std::map<GlobalValue::GUID, GlobalValueSummary *> &FunctionInfoMap) const {
  for (auto &GlobalList : *this) {
    auto GUID = GlobalList.first;
    for (auto &GlobInfo : GlobalList.second) {
      auto *Summary = dyn_cast_or_null<FunctionSummary>(GlobInfo->summary());
      if (!Summary)
        // Ignore global variable, focus on functions
        continue;
      // Ignore summaries from other modules.
      if (Summary->modulePath() != ModulePath)
        continue;
      FunctionInfoMap[GUID] = Summary;
    }
  }
}

// Collect for each module the list of function it defines (GUID -> Summary).
void ModuleSummaryIndex::collectDefinedGVSummariesPerModule(
    StringMap<std::map<GlobalValue::GUID, GlobalValueSummary *>> &
        Module2FunctionInfoMap) const {
  for (auto &GlobalList : *this) {
    auto GUID = GlobalList.first;
    for (auto &GlobInfo : GlobalList.second) {
      auto *Summary = GlobInfo->summary();
      Module2FunctionInfoMap[Summary->modulePath()][GUID] = Summary;
    }
  }
}

GlobalValueInfo *
ModuleSummaryIndex::getGlobalValueInfo(uint64_t ValueGUID,
                                       bool PerModuleIndex) const {
  auto InfoList = findGlobalValueInfoList(ValueGUID);
  assert(InfoList != end() && "GlobalValue not found in index");
  assert((!PerModuleIndex || InfoList->second.size() == 1) &&
         "Expected a single entry per global value in per-module index");
  auto &Info = InfoList->second[0];
  return Info.get();
}
