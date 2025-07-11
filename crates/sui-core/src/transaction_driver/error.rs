// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

use serde::{Deserialize, Serialize};
use sui_types::error::SuiError;
use thiserror::Error;

/// Client facing errors regarding transaction submission via Transaction Driver.
/// Every invariant needs detailed content to instruct client handling.
#[derive(Eq, PartialEq, Clone, Debug, Serialize, Deserialize, Error, Hash)]
pub enum TransactionDriverError {
    #[error("Serialization error: {0}")]
    SerializationError(SuiError),
    #[error("Deserialization error: {0}")]
    DeserializationError(SuiError),
    #[error("Transaction timed out getting consensus position")]
    TimeoutSubmittingTransaction,
    #[error("Transaction timed out before getting wait for effects response")]
    TimeoutWaitingForEffects,
    #[error("Transaction timed out before reaching finality")]
    TimeoutBeforeFinality,
    #[error("Failed to call validator {0}: {1}")]
    RpcFailure(String, String),
    #[error("Failed to find execution data: {0}")]
    ExecutionDataNotFound(String),
    #[error("Transaction rejected with reason: {0}")]
    TransactionRejected(String),
    #[error("Transaction expired at round: {0}")]
    TransactionExpired(String),
}
