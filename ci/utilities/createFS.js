const PackMule = require('aws-packmule');
const uuid = require('uuid/v1');

const options = {
    region: "us-east-1"
};

var packmule = new PackMule(options);

var tags = [
    {
        Key: "AAT_Service",
        Value: "Continuous_Integration"
    }
];

const token = uuid();

var fileSystemId;
packmule.createFS(token, tags, function(err, data) {
    if (err) {
        console.log(err, err.stack);
        return;
    }
    console.log(data);
    process.env.FILE_SYSTEM_ID = data.FileSystemId;
});
