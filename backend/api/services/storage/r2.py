"""Cloudflare R2 storage backend via S3-compatible API."""
from __future__ import annotations

from datetime import datetime
from typing import Iterable, Optional

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

from api.services.storage.base import StorageBackend, StorageObject


class R2Storage(StorageBackend):
    """R2-backed storage adapter using the S3 API."""
    def __init__(
        self,
        *,
        endpoint: str,
        bucket: str,
        access_key_id: str,
        secret_access_key: str,
    ) -> None:
        """Initialize the R2 storage client.

        Args:
            endpoint: R2 endpoint URL.
            bucket: Bucket name.
            access_key_id: Access key ID.
            secret_access_key: Secret access key.
        """
        self.bucket = bucket
        self.client = boto3.client(
            "s3",
            endpoint_url=endpoint,
            aws_access_key_id=access_key_id,
            aws_secret_access_key=secret_access_key,
            region_name="auto",
            config=Config(signature_version="s3v4"),
        )

    @staticmethod
    def _normalize_key(key: str) -> str:
        """Normalize a storage key by stripping leading slashes."""
        return key.lstrip("/")

    def list_objects(self, prefix: str, recursive: bool = True) -> Iterable[StorageObject]:
        """List objects in the bucket under a prefix.

        Args:
            prefix: Prefix to search under.
            recursive: Whether to list recursively. Defaults to True.

        Returns:
            Iterable of StorageObject metadata.
        """
        normalized = self._normalize_key(prefix)
        continuation = None
        results = []
        delimiter = None if recursive else "/"

        while True:
            params = {"Bucket": self.bucket, "Prefix": normalized}
            if continuation:
                params["ContinuationToken"] = continuation
            if delimiter:
                params["Delimiter"] = delimiter
            response = self.client.list_objects_v2(**params)

            for item in response.get("Contents", []):
                results.append(
                    StorageObject(
                        key=item["Key"],
                        size=item.get("Size", 0),
                        etag=item.get("ETag"),
                        last_modified=item.get("LastModified"),
                    )
                )

            if response.get("IsTruncated"):
                continuation = response.get("NextContinuationToken")
                continue
            break

        return results

    def get_object(self, key: str) -> bytes:
        """Retrieve object bytes by key."""
        normalized = self._normalize_key(key)
        response = self.client.get_object(Bucket=self.bucket, Key=normalized)
        return response["Body"].read()

    def get_object_range(self, key: str, start: int, end: int) -> bytes:
        """Retrieve a byte range by key."""
        normalized = self._normalize_key(key)
        response = self.client.get_object(
            Bucket=self.bucket,
            Key=normalized,
            Range=f"bytes={start}-{end}",
        )
        return response["Body"].read()

    def put_object(self, key: str, data: bytes, content_type: Optional[str] = None) -> StorageObject:
        """Store object bytes under a key."""
        normalized = self._normalize_key(key)
        params = {
            "Bucket": self.bucket,
            "Key": normalized,
            "Body": data,
        }
        if content_type:
            params["ContentType"] = content_type
        response = self.client.put_object(**params)
        etag = response.get("ETag")
        return StorageObject(key=normalized, size=len(data), etag=etag, content_type=content_type)

    def delete_object(self, key: str) -> None:
        """Delete an object by key."""
        normalized = self._normalize_key(key)
        self.client.delete_object(Bucket=self.bucket, Key=normalized)

    def copy_object(self, source_key: str, destination_key: str) -> None:
        """Copy an object to a new key."""
        source = {"Bucket": self.bucket, "Key": self._normalize_key(source_key)}
        destination = self._normalize_key(destination_key)
        self.client.copy_object(Bucket=self.bucket, CopySource=source, Key=destination)

    def object_exists(self, key: str) -> bool:
        """Return True if an object exists in the bucket."""
        normalized = self._normalize_key(key)
        try:
            self.client.head_object(Bucket=self.bucket, Key=normalized)
            return True
        except ClientError as exc:
            if exc.response.get("ResponseMetadata", {}).get("HTTPStatusCode") == 404:
                return False
            return False
