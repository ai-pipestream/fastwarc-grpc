// Copyright 2026 Kristian Rickert
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! Streaming gRPC server exposing the `fastwarc` WARC parser.
//!
//! The protobuf contracts live in `proto` and are linted with buf's
//! `STANDARD` and `COMMENTS` categories; the generated stubs are included
//! below in [`proto`]. See `DESIGN.md` for the architecture.

#![deny(missing_docs)]
#![warn(clippy::pedantic)]

pub mod convert;
pub mod warc_service;

/// Generated protobuf and gRPC stubs.
///
/// The stubs carry no doc comments or clippy annotations of their own; the
/// commented, linted source of truth is the schema in `proto`.
#[allow(missing_docs, clippy::all, clippy::pedantic, clippy::nursery)]
pub mod proto {
    /// Encoded descriptor set of the `fastwarc.v1` package, for server
    /// reflection.
    pub const FILE_DESCRIPTOR_SET: &[u8] = tonic::include_file_descriptor_set!("descriptor");

    /// Stubs for the `fastwarc.v1` package.
    pub mod fastwarc {
        /// Messages and `WarcService` server/client stubs.
        pub mod v1 {
            tonic::include_proto!("fastwarc.v1");
        }
    }
}
