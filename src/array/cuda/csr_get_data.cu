/*!
 *  Copyright (c) 2021 by Contributors
 * \file array/cuda/csr_get_data.cu
 * \brief Retrieve entries of a CSR matrix
 */
#include <dgl/array.h>
#include <vector>
#include <unordered_set>
#include <numeric>
#include "../../runtime/cuda/cuda_common.h"
#include "./utils.h"

namespace dgl {

using runtime::NDArray;

namespace aten {
namespace impl {

template <DGLDeviceType XPU, typename IdType, typename DType>
NDArray CSRGetData(
    CSRMatrix csr, NDArray rows, NDArray cols, bool return_eids, NDArray weights, DType filler) {
  const int64_t rowlen = rows->shape[0];
  const int64_t collen = cols->shape[0];

  CHECK((rowlen == collen) || (rowlen == 1) || (collen == 1))
    << "Invalid row and col id array.";

  const int64_t row_stride = (rowlen == 1 && collen != 1) ? 0 : 1;
  const int64_t col_stride = (collen == 1 && rowlen != 1) ? 0 : 1;

  const int64_t rstlen = std::max(rowlen, collen);
  IdArray rst = NDArray::Empty({rstlen}, weights->dtype, rows->ctx);
  if (rstlen == 0)
    return rst;

  cudaStream_t stream = runtime::getCurrentCUDAStream();
  const int nt = cuda::FindNumThreads(rstlen);
  const int nb = (rstlen + nt - 1) / nt;
  if (return_eids)
    BUG_IF_FAIL(DGLDataTypeTraits<DType>::dtype == rows->dtype) <<
      "DType does not match row's dtype.";

  const IdType* indptr_data = csr.indptr.Ptr<IdType>();
  const IdType* indices_data = csr.indices.Ptr<IdType>();
  const IdType* data_data = CSRHasData(csr) ? csr.data.Ptr<IdType>() : nullptr;
  if (csr.is_pinned) {
    CUDA_CALL(cudaHostGetDevicePointer(
        &indptr_data, csr.indptr.Ptr<IdType>(), 0));
    CUDA_CALL(cudaHostGetDevicePointer(
        &indices_data, csr.indices.Ptr<IdType>(), 0));
    if (CSRHasData(csr)) {
      CUDA_CALL(cudaHostGetDevicePointer(
          &data_data, csr.data.Ptr<IdType>(), 0));
    }
  }

  // TODO(minjie): use binary search for sorted csr
  CUDA_KERNEL_CALL(cuda::_LinearSearchKernel,
      nb, nt, 0, stream,
      indptr_data, indices_data, data_data,
      rows.Ptr<IdType>(), cols.Ptr<IdType>(),
      row_stride, col_stride, rstlen,
      return_eids ? nullptr : weights.Ptr<DType>(), filler, rst.Ptr<DType>());
  return rst;
}

#ifdef USE_FP16
template NDArray CSRGetData<kDGLCUDA, int32_t, __half>(
    CSRMatrix csr, NDArray rows, NDArray cols, bool return_eids, NDArray weights, __half filler);
template NDArray CSRGetData<kDGLCUDA, int64_t, __half>(
    CSRMatrix csr, NDArray rows, NDArray cols, bool return_eids, NDArray weights, __half filler);
#endif
template NDArray CSRGetData<kDGLCUDA, int32_t, float>(
    CSRMatrix csr, NDArray rows, NDArray cols, bool return_eids, NDArray weights, float filler);
template NDArray CSRGetData<kDGLCUDA, int64_t, float>(
    CSRMatrix csr, NDArray rows, NDArray cols, bool return_eids, NDArray weights, float filler);
template NDArray CSRGetData<kDGLCUDA, int32_t, double>(
    CSRMatrix csr, NDArray rows, NDArray cols, bool return_eids, NDArray weights, double filler);
template NDArray CSRGetData<kDGLCUDA, int64_t, double>(
    CSRMatrix csr, NDArray rows, NDArray cols, bool return_eids, NDArray weights, double filler);

// For CSRGetData<XPU, IdType>(CSRMatrix, NDArray, NDArray)
template NDArray CSRGetData<kDGLCUDA, int32_t, int32_t>(
    CSRMatrix csr, NDArray rows, NDArray cols, bool return_eids, NDArray weights, int32_t filler);
template NDArray CSRGetData<kDGLCUDA, int64_t, int64_t>(
    CSRMatrix csr, NDArray rows, NDArray cols, bool return_eids, NDArray weights, int64_t filler);

}  // namespace impl
}  // namespace aten
}  // namespace dgl
