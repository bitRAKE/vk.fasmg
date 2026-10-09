// One GPU pointer is the complete command interface. All arrays and mutable
// arguments are resident in an application-owned, mapped GPU allocation.
struct Arguments
{
    Ptr<uint, Access.Read> input_a;
    Ptr<uint, Access.Read> input_b;
    uint* output;
    uint count;
    uint bias;
};
struct Root
{
    Ptr<Arguments, Access.Read> arguments;
};
[[vk::push_constant]] ConstantBuffer<Root> root;

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    Ptr<Arguments, Access.Read> args = root.arguments;
    uint i = id.x;
    if (i < args->count)
        args->output[i] = args->input_a[i] + args->input_b[i] + args->bias;
}
