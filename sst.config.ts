/// <reference path="./.sst/platform/config.d.ts" />

export default $config({
  app(input) {
    return {
      name: "station",
      removal: "remove",
      home: "aws",
      providers: {
        aws: {
          region: "ap-southeast-1",
          profile: "tanle",
        },
      },
    };
  },
  async run() {
    const domain = "station.tanlethanh.me";
    
    const cdn = new sst.aws.Cdn("StationCdn", {
      domain,
      origins: [{
        originId: "github",
        domainName: "raw.githubusercontent.com",
        originPath: "/tanlethanh/station/main",
        customOriginConfig: {
          httpPort: 80,
          httpsPort: 443,
          originProtocolPolicy: "https-only",
          originSslProtocols: ["TLSv1.2"],
        },
      }],
      defaultCacheBehavior: {
        targetOriginId: "github",
        viewerProtocolPolicy: "redirect-to-https",
        allowedMethods: ["GET", "HEAD", "OPTIONS"],
        cachedMethods: ["GET", "HEAD"],
        compress: true,
        cachePolicyId: "658327ea-f89d-4fab-a63d-7e88639e58f6", // Managed-CachingOptimized
      },
    });

    return { domain, url: cdn.url };
  },
});


