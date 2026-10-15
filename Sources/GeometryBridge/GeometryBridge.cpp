#include "GeometryBridge.h"
#include "clipper2/clipper.h"
#include <cstdlib>
#include <cmath>
#include <functional>
using namespace Clipper2Lib;
static EGPaths resolve(const double *xy, const int32_t *counts, int32_t count, double delta, bool nonzero, bool hierarchy=false) {
    EGPaths result{};
    try {
        if (!xy || !counts || count < 1 || count > 1024 || !std::isfinite(delta) || std::abs(delta)>10) { result.error=1; return result; }
        PathsD input; size_t cursor=0;
        for (int32_t r=0;r<count;++r) {
            if (counts[r]<3 || counts[r]>20000) { result.error=1; return result; }
            PathD path;
            for(int32_t i=0;i<counts[r];++i) {
                double x=xy[cursor++],y=xy[cursor++];
                if(!std::isfinite(x)||!std::isfinite(y)||std::abs(x)>10000||std::abs(y)>10000) { result.error=1; return result; }
                path.emplace_back(x,y);
            }
            input.push_back(path);
        }
        PathsD output; std::vector<int32_t> parents;
        if (hierarchy) {
            ClipperD clipper(4); clipper.AddSubject(input); PolyTreeD tree;
            if (!clipper.Execute(ClipType::Union, nonzero ? FillRule::NonZero : FillRule::EvenOdd, tree)) { result.error=4; return result; }
            std::function<void(const PolyPathD&, int32_t)> visit = [&](const PolyPathD& node, int32_t parent) {
                for (const auto& child: node) {
                    const auto index=static_cast<int32_t>(output.size());
                    output.push_back(child->Polygon()); parents.push_back(parent); visit(*child,index);
                }
            };
            visit(tree,-1);
        } else {
            auto clean=Union(input,FillRule::EvenOdd,4);
            output=std::abs(delta)<1e-9 ? clean : InflatePaths(clean,delta,JoinType::Round,EndType::Polygon,2.0,4,0.02);
        }
        size_t points=0; for(const auto &path:output) points+=path.size();
        if(points>200000 || output.size()>1024) { result.error=2; return result; }
        if(output.empty()) return result;
        result.xy=static_cast<double*>(std::malloc(points*2*sizeof(double)));
        result.counts=static_cast<int32_t*>(std::malloc(output.size()*sizeof(int32_t)));
        if(hierarchy) result.parents=static_cast<int32_t*>(std::malloc(output.size()*sizeof(int32_t)));
        if(!result.xy||!result.counts||(hierarchy&&!result.parents)) { eg_free_paths(result); return EGPaths{nullptr,nullptr,0,0,3}; }
        result.path_count=static_cast<int32_t>(output.size()); result.point_count=static_cast<int32_t>(points);
        cursor=0;
        for(size_t r=0;r<output.size();++r) {
            result.counts[r]=static_cast<int32_t>(output[r].size());
            if(hierarchy) result.parents[r]=parents[r];
            for(const auto &p:output[r]) { result.xy[cursor++]=p.x; result.xy[cursor++]=p.y; }
        }
    } catch(...) { eg_free_paths(result); return EGPaths{nullptr,nullptr,0,0,4}; }
    return result;
}
extern "C" void eg_free_paths(EGPaths result) { std::free(result.xy); std::free(result.counts); std::free(result.parents); }

extern "C" EGPaths eg_offset(const double *xy,const int32_t *counts,int32_t count,double delta) { return resolve(xy,counts,count,delta,false); }
extern "C" EGPaths eg_resolve(const double *xy,const int32_t *counts,int32_t count,int32_t nonzero) { return resolve(xy,counts,count,0,nonzero!=0,true); }

// Reads `count` rings of mm coordinates (same limits as resolve); false if any ring or point is out of range.
static bool read_paths(const double *xy, const int32_t *counts, int32_t count, PathsD &paths) {
    if (!xy || !counts || count < 1 || count > 1024) return false;
    size_t cursor=0;
    for (int32_t r=0;r<count;++r) {
        if (counts[r]<3 || counts[r]>20000) return false;
        PathD path;
        for(int32_t i=0;i<counts[r];++i) {
            double x=xy[cursor++],y=xy[cursor++];
            if(!std::isfinite(x)||!std::isfinite(y)||std::abs(x)>10000||std::abs(y)>10000) return false;
            path.emplace_back(x,y);
        }
        paths.push_back(path);
    }
    return true;
}

extern "C" EGPaths eg_difference(const double *subject_xy,const int32_t *subject_counts,int32_t subject_count,
                                 const double *clip_xy,const int32_t *clip_counts,int32_t clip_count) {
    EGPaths result{};
    try {
        PathsD subject, clip;
        if (!read_paths(subject_xy,subject_counts,subject_count,subject) || !read_paths(clip_xy,clip_counts,clip_count,clip)) { result.error=1; return result; }
        ClipperD clipper(4); clipper.AddSubject(subject); clipper.AddClip(clip); PolyTreeD tree;
        if (!clipper.Execute(ClipType::Difference, FillRule::EvenOdd, tree)) { result.error=4; return result; }
        // Flatten the tree into rings plus each ring's parent, as eg_resolve does.
        PathsD output; std::vector<int32_t> parents;
        std::function<void(const PolyPathD&, int32_t)> visit = [&](const PolyPathD& node, int32_t parent) {
            for (const auto& child: node) {
                const auto index=static_cast<int32_t>(output.size());
                output.push_back(child->Polygon()); parents.push_back(parent); visit(*child,index);
            }
        };
        visit(tree,-1);
        size_t points=0; for(const auto &path:output) points+=path.size();
        if(points>200000 || output.size()>1024) { result.error=2; return result; }
        if(output.empty()) return result;
        result.xy=static_cast<double*>(std::malloc(points*2*sizeof(double)));
        result.counts=static_cast<int32_t*>(std::malloc(output.size()*sizeof(int32_t)));
        result.parents=static_cast<int32_t*>(std::malloc(output.size()*sizeof(int32_t)));
        if(!result.xy||!result.counts||!result.parents) { eg_free_paths(result); return EGPaths{nullptr,nullptr,0,0,3,nullptr}; }
        result.path_count=static_cast<int32_t>(output.size()); result.point_count=static_cast<int32_t>(points);
        size_t cursor=0;
        for(size_t r=0;r<output.size();++r) {
            result.counts[r]=static_cast<int32_t>(output[r].size()); result.parents[r]=parents[r];
            for(const auto &p:output[r]) { result.xy[cursor++]=p.x; result.xy[cursor++]=p.y; }
        }
    } catch(...) { eg_free_paths(result); return EGPaths{nullptr,nullptr,0,0,4,nullptr}; }
    return result;
}
