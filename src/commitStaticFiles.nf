process commitStaticFiles {
    time '10m'

    input:
      file messagepack
      file summary_gzip
      val geo_type

    script:
    """
    #!/bin/bash

    GZIP="--content-encoding gzip"
    PUBLIC="--acl public-read"
    MSGPACK="--content-type application/x-msgpack"
    CACHE="--cache-control max-age=3600"
    S3_BUCKET="s3://covidestim"
    CLOUDFRONT_DISTRO="E3LRZT05X19VF9"

    case $geo_type in
      fips)  PRODUCTION_PATH="latest-v2";;
      state) PRODUCTION_PATH="latest-v2/state";;
      *)     echo "Unsupported geo_type '$geo_type', exiting!" && exit 2;;
    esac

    # Move the MessagePack and .csv.gz files into the production bucket
    aws s3 cp \$GZIP \$PUBLIC \$MSGPACK \$CACHE "$messagepack"  "\$S3_BUCKET/\$PRODUCTION_PATH/summary.pack.gz"
    aws s3 cp \$GZIP \$PUBLIC                   "$summary_gzip" "\$S3_BUCKET/\$PRODUCTION_PATH/estimates.csv"

    # Invalidate the CDN's existing copies
    aws cloudfront create-invalidation \
      --distribution-id \$CLOUDFRONT_DISTRO \
      --paths "/\$PRODUCTION_PATH/summary.pack.gz /\$PRODUCTION_PATH/estimates.csv"
    """
}
